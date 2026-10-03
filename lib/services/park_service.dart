import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/park.dart';

/// Parks found in the app bundle plus any files that could not be read.
class ParkLoadResult {
  const ParkLoadResult({required this.parks, required this.errors});

  final List<Park> parks;

  /// One message per park file that failed to load.
  final List<String> errors;
}

/// Loads park boundaries from every `parks/*.geojson` asset.
///
/// No file list is hard-coded: drop a GeoJSON into `parks/`, run
/// `tools/build_map.py` and rebuild the app.
class ParkService {
  ParkService._();

  static final ParkService instance = ParkService._();

  static const String parksDirectory = 'parks/';

  ParkLoadResult? _cache;

  Future<ParkLoadResult> loadParks({AssetBundle? bundle}) async {
    final cached = _cache;
    if (cached != null) return cached;

    final assets = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(assets);
    final files = manifest
        .listAssets()
        .where((a) =>
            a.startsWith(parksDirectory) && a.toLowerCase().endsWith('.geojson'))
        .toList()
      ..sort();

    final parks = <Park>[];
    final errors = <String>[];
    for (final asset in files) {
      final fileName = asset.substring(parksDirectory.length);
      try {
        final text = await assets.loadString(asset);
        parks.add(parseParkGeoJson(text, fileName: fileName));
      } catch (e) {
        errors.add('$fileName: $e');
      }
    }
    parks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _cache = ParkLoadResult(parks: parks, errors: errors);
  }

  /// Clears the cache (used by tests).
  void clearCache() => _cache = null;
}

/// `MI_0005_GrandHavenParks.geojson` -> `Grand Haven Parks`.
String parkNameFromFileName(String fileName) {
  var stem = fileName;
  final dot = stem.lastIndexOf('.');
  if (dot > 0) stem = stem.substring(0, dot);

  final parts = stem.split('_');
  var core = stem;
  if (parts.length >= 3 &&
      RegExp(r'^[A-Za-z]+$').hasMatch(parts[0]) &&
      RegExp(r'^\d+$').hasMatch(parts[1])) {
    core = parts.sublist(2).join('_');
  }
  core = core
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return core.isEmpty ? stem : core;
}

/// Parses a park GeoJSON (FeatureCollection, Feature or bare geometry).
/// Every Polygon / MultiPolygon becomes a [ParkArea]; other geometry types
/// are ignored. Throws [FormatException] with a readable message.
Park parseParkGeoJson(String text, {required String fileName}) {
  var source = text;
  if (source.startsWith('\uFEFF')) source = source.substring(1);

  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (e) {
    throw FormatException('invalid JSON (${e.message})');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('top level must be a GeoJSON object');
  }

  final List<dynamic> features;
  switch (decoded['type']) {
    case 'FeatureCollection':
      features = (decoded['features'] as List<dynamic>?) ?? const [];
    case 'Feature':
      features = [decoded];
    default:
      features = [
        {'type': 'Feature', 'properties': <String, dynamic>{}, 'geometry': decoded},
      ];
  }

  String? name;
  final areas = <ParkArea>[];
  for (var i = 0; i < features.length; i++) {
    final feature = features[i];
    if (feature is! Map) continue;
    final props = feature['properties'];
    if (name == null && props is Map) {
      for (final key in const ['name', 'Name', 'NAME', 'park_name', 'title']) {
        final value = props[key];
        if (value is String && value.trim().isNotEmpty) {
          name = value.trim();
          break;
        }
      }
    }
    areas.addAll(_areasFromGeometry(feature['geometry'], 'feature ${i + 1}'));
  }

  if (areas.isEmpty) {
    throw const FormatException('no Polygon or MultiPolygon geometry found');
  }

  final dot = fileName.lastIndexOf('.');
  final id = dot > 0 ? fileName.substring(0, dot) : fileName;
  return Park(
    id: id,
    name: name ?? parkNameFromFileName(fileName),
    areas: areas,
    sourceFile: fileName,
  );
}

List<ParkArea> _areasFromGeometry(Object? geometry, String where) {
  if (geometry is! Map) return const [];
  final coordinates = geometry['coordinates'];
  switch (geometry['type']) {
    case 'Polygon':
      return [_polygon(coordinates, where)];
    case 'MultiPolygon':
      if (coordinates is! List) {
        throw FormatException('$where: MultiPolygon coordinates missing');
      }
      return [
        for (var i = 0; i < coordinates.length; i++)
          _polygon(coordinates[i], '$where polygon ${i + 1}'),
      ];
    case 'GeometryCollection':
      final geometries = geometry['geometries'];
      if (geometries is! List) return const [];
      return [
        for (var i = 0; i < geometries.length; i++)
          ..._areasFromGeometry(geometries[i], '$where geometry ${i + 1}'),
      ];
    default:
      return const [];
  }
}

ParkArea _polygon(Object? rings, String where) {
  if (rings is! List || rings.isEmpty) {
    throw FormatException('$where: polygon has no rings');
  }
  final outer = _ring(rings.first, '$where outer ring');
  final holes = <List<LatLng>>[
    for (var i = 1; i < rings.length; i++) _ring(rings[i], '$where hole $i'),
  ];
  return ParkArea(outer: outer, holes: holes);
}

List<LatLng> _ring(Object? positions, String where) {
  if (positions is! List) throw FormatException('$where: not a list');
  final ring = <LatLng>[];
  for (final position in positions) {
    if (position is! List || position.length < 2) {
      throw FormatException('$where: position $position is not [lon, lat]');
    }
    final lon = position[0];
    final lat = position[1];
    if (lon is! num || lat is! num) {
      throw FormatException('$where: position $position is not numeric');
    }
    final lonD = lon.toDouble();
    final latD = lat.toDouble();
    if (!lonD.isFinite || !latD.isFinite || lonD.abs() > 180 || latD.abs() > 90) {
      final swapped = latD.abs() <= 180 && lonD.abs() <= 90;
      throw FormatException(
          '$where: position $position is out of range'
          '${swapped ? ' (GeoJSON must be [lon, lat])' : ''}');
    }
    ring.add(LatLng(latD, lonD));
  }
  if (ring.length >= 2 &&
      ring.first.latitude == ring.last.latitude &&
      ring.first.longitude == ring.last.longitude) {
    ring.removeLast();
  }
  if (ring.length < 3) {
    throw FormatException('$where: needs at least 3 positions');
  }
  return ring;
}
