import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Axis-aligned latitude/longitude box.
@immutable
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  factory GeoBounds.fromPoints(Iterable<LatLng> points) {
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    var any = false;
    for (final p in points) {
      any = true;
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    if (!any) {
      throw ArgumentError('GeoBounds.fromPoints needs at least one point');
    }
    return GeoBounds(south: south, west: west, north: north, east: east);
  }

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;

  GeoBounds union(GeoBounds other) => GeoBounds(
        south: math.min(south, other.south),
        west: math.min(west, other.west),
        north: math.max(north, other.north),
        east: math.max(east, other.east),
      );

  LatLng get southWest => LatLng(south, west);
  LatLng get northEast => LatLng(north, east);
  LatLng get center => LatLng((south + north) / 2, (west + east) / 2);
}

/// Even-odd point-in-polygon test. Works for open and closed rings and
/// counts every edge exactly once (half-open crossing rule).
bool ringContains(List<LatLng> ring, double lat, double lng) {
  var inside = false;
  final n = ring.length;
  if (n < 3) return false;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final yi = ring[i].latitude;
    final xi = ring[i].longitude;
    final yj = ring[j].latitude;
    final xj = ring[j].longitude;
    if ((yi > lat) != (yj > lat)) {
      final xCross = (xj - xi) * (lat - yi) / (yj - yi) + xi;
      if (lng < xCross) inside = !inside;
    }
  }
  return inside;
}

/// One polygon of a park (outer boundary plus optional holes).
@immutable
class ParkArea {
  ParkArea({required this.outer, this.holes = const []})
      : bounds = GeoBounds.fromPoints(outer);

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
  final GeoBounds bounds;

  bool contains(double lat, double lng) {
    if (!bounds.contains(lat, lng)) return false;
    if (!ringContains(outer, lat, lng)) return false;
    for (final hole in holes) {
      if (ringContains(hole, lat, lng)) return false;
    }
    return true;
  }
}

/// A park declared by a GeoJSON file in `parks/`. A park can consist of
/// several separate areas (MultiPolygon or several features); navigation
/// works inside the area the user is currently in.
@immutable
class Park {
  Park({
    required this.id,
    required this.name,
    required this.areas,
    required this.sourceFile,
  }) : bounds = areas
            .map((a) => a.bounds)
            .reduce((value, element) => value.union(element));

  final String id;
  final String name;
  final List<ParkArea> areas;
  final String sourceFile;
  final GeoBounds bounds;

  /// Index of the area containing the point, or null when outside the park.
  int? areaIndexAt(double lat, double lng) {
    if (!bounds.contains(lat, lng)) return null;
    for (var i = 0; i < areas.length; i++) {
      if (areas[i].contains(lat, lng)) return i;
    }
    return null;
  }

  bool containsPoint(double lat, double lng) => areaIndexAt(lat, lng) != null;

  /// Human readable label for an area ("area 2 of 3"), empty for single-area parks.
  String areaLabel(int index) =>
      areas.length > 1 ? 'area ${index + 1} of ${areas.length}' : '';
}

/// Which park (and area) a location belongs to.
class ParkMembership {
  const ParkMembership(this.park, this.areaIndex);

  final Park park;
  final int areaIndex;
}

/// First park whose areas contain the location, or null.
ParkMembership? findParkMembership(List<Park> parks, double lat, double lng) {
  for (final park in parks) {
    final area = park.areaIndexAt(lat, lng);
    if (area != null) return ParkMembership(park, area);
  }
  return null;
}
