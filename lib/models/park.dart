import 'package:latlong2/latlong.dart';

/// Represents a park area with its boundary polygon
class Park {
  const Park({
    required this.id,
    required this.name,
    required this.boundary,
  });

  final String id;
  final String name;
  final List<LatLng> boundary; // Polygon coordinates

  /// Check if a point is inside the park boundary using ray casting algorithm
  bool containsPoint(double lat, double lng) {
    int intersections = 0;
    for (int i = 0; i < boundary.length - 1; i++) {
      final p1 = boundary[i];
      final p2 = boundary[i + 1];

      if (_rayIntersectsSegment(lat, lng, p1, p2)) {
        intersections++;
      }
    }
    return intersections % 2 == 1;
  }

  bool _rayIntersectsSegment(double lat, double lng, LatLng p1, LatLng p2) {
    if (p1.latitude > p2.latitude) {
      return _rayIntersectsSegment(lat, lng, p2, p1);
    }

    if (lat < p1.latitude || lat > p2.latitude) {
      return false;
    }

    if (lng >= p1.longitude && lng >= p2.longitude) {
      return false;
    }

    if (lng < p1.longitude && lng < p2.longitude) {
      return true;
    }

    final slope = (p2.longitude - p1.longitude) / (p2.latitude - p1.latitude);
    final x = p1.longitude + (lat - p1.latitude) * slope;
    return lng < x;
  }

  /// Get center point of the park (average of all boundary points)
  LatLng get center {
    double sumLat = 0;
    double sumLng = 0;
    for (final point in boundary) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    return LatLng(
      sumLat / boundary.length,
      sumLng / boundary.length,
    );
  }

  /// Get bounds for fitting the park on the map
  ({LatLng southwest, LatLng northeast}) get bounds {
    double minLat = boundary.first.latitude;
    double maxLat = boundary.first.latitude;
    double minLng = boundary.first.longitude;
    double maxLng = boundary.first.longitude;

    for (final point in boundary) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return (
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
