import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/park.dart';

/// Service to load and manage park data from GeoJSON files
class ParkService {
  ParkService._();
  
  static final ParkService instance = ParkService._();
  
  List<Park>? _cachedParks;
  
  /// List of park files to load
  static const _parkFiles = [
    'parks/MI_1001_MuligansHollow.geojson',
    'parks/MI_1002_DuncanPark.geojson',
    'parks/MI_1003_LakeForestCemetery.geojson',
    'parks/MI_1004_EscanabaPark.geojson',
    'parks/MI_1101_AppleRidge.geojson',
    'parks/MI_1102_GVSU.geojson',
  ];
  
  /// Load all parks from the parks/ directory
  Future<List<Park>> loadParks() async {
    if (_cachedParks != null) {
      return _cachedParks!;
    }
    
    final parks = <Park>[];
    
    // Load each park file
    for (final assetPath in _parkFiles) {
      final parkName = _extractParkName(assetPath);
      final parkData = await _loadParkFromAsset(assetPath, parkName);
      if (parkData != null) {
        parks.add(parkData);
      }
    }
    
    _cachedParks = parks;
    return parks;
  }
  
  /// Extract human-readable park name from file path
  String _extractParkName(String assetPath) {
    final filename = assetPath.split('/').last;
    final nameWithoutExt = filename.replaceAll('.geojson', '');
    
    // Extract park name from format: MI_0005_GrandHavenParks
    final parts = nameWithoutExt.split('_');
    if (parts.length >= 3) {
      // Convert CamelCase to spaces
      final name = parts.sublist(2).join('_');
      return name.replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      );
    }
    return nameWithoutExt;
  }
  
  /// Load a single park from a GeoJSON asset
  Future<Park?> _loadParkFromAsset(String assetPath, String parkName) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final data = json.decode(jsonString) as Map<String, dynamic>;
      
      // Parse GeoJSON FeatureCollection
      if (data['type'] != 'FeatureCollection') {
        throw FormatException('Expected FeatureCollection, got ${data['type']}');
      }
      
      final features = data['features'] as List;
      if (features.isEmpty) {
        throw FormatException('No features found in $assetPath');
      }
      
      // Get the first feature (polygon)
      final feature = features.first as Map<String, dynamic>;
      final geometry = feature['geometry'] as Map<String, dynamic>;
      
      if (geometry['type'] != 'Polygon') {
        throw FormatException('Expected Polygon, got ${geometry['type']}');
      }
      
      // Parse coordinates
      final coordinates = geometry['coordinates'] as List;
      final ring = coordinates.first as List; // Outer ring
      
      final boundary = <LatLng>[];
      for (final coord in ring) {
        final point = coord as List;
        final lng = (point[0] as num).toDouble();
        final lat = (point[1] as num).toDouble();
        boundary.add(LatLng(lat, lng));
      }
      
      // Extract park ID from filename
      final parkId = assetPath.split('/').last.replaceAll('.geojson', '');
      
      return Park(
        id: parkId,
        name: parkName,
        boundary: boundary,
      );
    } catch (e) {
      print('Error loading park from $assetPath: $e');
      return null;
    }
  }
  
  /// Clear cached parks (useful for testing)
  void clearCache() {
    _cachedParks = null;
  }
}
