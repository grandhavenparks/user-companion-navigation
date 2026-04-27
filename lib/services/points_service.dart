import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Represents a point from the points CSV files
class ParkPoint {
  const ParkPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  LatLng toLatLng() => LatLng(latitude, longitude);
}

/// Service to load and manage points from CSV files
class PointsService {
  PointsService._();
  
  static final PointsService instance = PointsService._();
  
  /// Create a closed loop polygon that includes ALL points on edges
  /// Uses convex hull + iterative point insertion to avoid intersections
  List<LatLng> createClosedLoop(List<ParkPoint> points) {
    if (points.isEmpty) return [];
    if (points.length == 1) return [points.first.toLatLng()];
    if (points.length == 2) {
      return [points[0].toLatLng(), points[1].toLatLng(), points[0].toLatLng()];
    }
    
    // Convert to LatLng for processing
    final latLngPoints = points.map((p) => p.toLatLng()).toList();
    
    // Step 1: Compute convex hull
    final hull = _computeConvexHull(latLngPoints);
    
    // Step 2: Initialize polygon with convex hull
    final polygon = List<LatLng>.from(hull);
    
    // Step 3: Find interior points (not in hull)
    final interior = <LatLng>[];
    for (final point in latLngPoints) {
      if (!_isInList(point, hull)) {
        interior.add(point);
      }
    }
    
    // Step 4: Insert interior points into edges
    for (final interiorPoint in interior) {
      _insertPointIntoPolygon(polygon, interiorPoint);
    }
    
    // Step 5: Close the loop
    if (polygon.isNotEmpty && !_pointsEqual(polygon.first, polygon.last)) {
      polygon.add(polygon.first);
    }
    
    return polygon;
  }
  
  /// Insert a point into the polygon at the best edge (no intersections)
  void _insertPointIntoPolygon(List<LatLng> polygon, LatLng point) {
    double bestDistance = double.infinity;
    int bestIndex = -1;
    
    // Try each edge to find the closest one that doesn't cause intersections
    for (int i = 0; i < polygon.length - 1; i++) {
      final v1 = polygon[i];
      final v2 = polygon[i + 1];
      
      // Check if inserting point between v1 and v2 creates intersections
      if (!_wouldCauseIntersection(polygon, i, point)) {
        // Calculate distance from point to edge
        final dist = _distanceToSegment(point, v1, v2);
        if (dist < bestDistance) {
          bestDistance = dist;
          bestIndex = i;
        }
      }
    }
    
    // Insert at best position found
    if (bestIndex >= 0) {
      polygon.insert(bestIndex + 1, point);
    } else {
      // Fallback: insert at position with minimum distance (may cause slight issues)
      // Find closest edge
      double minDist = double.infinity;
      int minIndex = 0;
      for (int i = 0; i < polygon.length - 1; i++) {
        final dist = _distanceToSegment(point, polygon[i], polygon[i + 1]);
        if (dist < minDist) {
          minDist = dist;
          minIndex = i;
        }
      }
      polygon.insert(minIndex + 1, point);
    }
  }
  
  /// Check if inserting point at index would cause intersections with other edges
  bool _wouldCauseIntersection(List<LatLng> polygon, int edgeIndex, LatLng point) {
    final v1 = polygon[edgeIndex];
    final v2 = polygon[edgeIndex + 1];
    
    // Check if new edges (v1,point) and (point,v2) intersect with any existing edges
    for (int i = 0; i < polygon.length - 1; i++) {
      // Skip adjacent edges
      if (i == edgeIndex || i == edgeIndex - 1 || i == edgeIndex + 1) {
        continue;
      }
      
      final e1 = polygon[i];
      final e2 = polygon[i + 1];
      
      // Check if (v1, point) intersects with (e1, e2)
      if (_segmentsIntersect(v1, point, e1, e2)) {
        return true;
      }
      
      // Check if (point, v2) intersects with (e1, e2)
      if (_segmentsIntersect(point, v2, e1, e2)) {
        return true;
      }
    }
    
    return false;
  }
  
  /// Check if two line segments intersect
  bool _segmentsIntersect(LatLng p1, LatLng p2, LatLng p3, LatLng p4) {
    final d1 = _direction(p3, p4, p1);
    final d2 = _direction(p3, p4, p2);
    final d3 = _direction(p1, p2, p3);
    final d4 = _direction(p1, p2, p4);
    
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    
    // Check for collinear overlaps
    if (d1 == 0 && _onSegment(p3, p4, p1)) return true;
    if (d2 == 0 && _onSegment(p3, p4, p2)) return true;
    if (d3 == 0 && _onSegment(p1, p2, p3)) return true;
    if (d4 == 0 && _onSegment(p1, p2, p4)) return true;
    
    return false;
  }
  
  /// Calculate direction using cross product
  double _direction(LatLng a, LatLng b, LatLng c) {
    return (c.longitude - a.longitude) * (b.latitude - a.latitude) -
        (b.longitude - a.longitude) * (c.latitude - a.latitude);
  }
  
  /// Check if point c is on segment (a, b)
  bool _onSegment(LatLng a, LatLng b, LatLng c) {
    return c.longitude <= math.max(a.longitude, b.longitude) &&
        c.longitude >= math.min(a.longitude, b.longitude) &&
        c.latitude <= math.max(a.latitude, b.latitude) &&
        c.latitude >= math.min(a.latitude, b.latitude);
  }
  
  /// Calculate distance from point to line segment
  double _distanceToSegment(LatLng point, LatLng v1, LatLng v2) {
    final dx = v2.longitude - v1.longitude;
    final dy = v2.latitude - v1.latitude;
    
    if (dx == 0 && dy == 0) {
      // v1 and v2 are the same point
      return _distance(point, v1);
    }
    
    // Calculate projection of point onto line
    final t = ((point.longitude - v1.longitude) * dx +
            (point.latitude - v1.latitude) * dy) /
        (dx * dx + dy * dy);
    
    if (t < 0) {
      // Closest to v1
      return math.sqrt(_distance(point, v1));
    } else if (t > 1) {
      // Closest to v2
      return math.sqrt(_distance(point, v2));
    } else {
      // Closest to point on segment
      final projX = v1.longitude + t * dx;
      final projY = v1.latitude + t * dy;
      final projPoint = LatLng(projY, projX);
      return math.sqrt(_distance(point, projPoint));
    }
  }
  
  /// Check if point is in list (with tolerance)
  bool _isInList(LatLng point, List<LatLng> list) {
    for (final p in list) {
      if (_pointsEqual(point, p)) {
        return true;
      }
    }
    return false;
  }
  
  /// Check if two points are equal (with small tolerance)
  bool _pointsEqual(LatLng a, LatLng b) {
    const tolerance = 0.0000001;
    return (a.latitude - b.latitude).abs() < tolerance &&
        (a.longitude - b.longitude).abs() < tolerance;
  }
  
  /// Compute convex hull using Graham scan algorithm
  /// Returns points in counter-clockwise order forming a non-intersecting polygon
  List<LatLng> _computeConvexHull(List<LatLng> points) {
    if (points.length < 3) return List.from(points);
    
    // Find the point with lowest latitude (bottom-most), use longitude as tiebreaker
    LatLng pivot = points[0];
    for (final point in points) {
      if (point.latitude < pivot.latitude ||
          (point.latitude == pivot.latitude && point.longitude < pivot.longitude)) {
        pivot = point;
      }
    }
    
    // Sort points by polar angle with respect to pivot
    final sortedPoints = List<LatLng>.from(points);
    sortedPoints.remove(pivot);
    sortedPoints.sort((a, b) {
      final angleA = _polarAngle(pivot, a);
      final angleB = _polarAngle(pivot, b);
      
      if (angleA < angleB) return -1;
      if (angleA > angleB) return 1;
      
      // If angles are equal, sort by distance
      final distA = _distance(pivot, a);
      final distB = _distance(pivot, b);
      return distA.compareTo(distB);
    });
    
    // Build hull using stack
    final hull = <LatLng>[pivot];
    
    for (final point in sortedPoints) {
      // Remove points that would make a right turn
      while (hull.length >= 2 &&
          _crossProduct(hull[hull.length - 2], hull[hull.length - 1], point) <= 0) {
        hull.removeLast();
      }
      hull.add(point);
    }
    
    return hull;
  }
  
  /// Calculate polar angle from pivot to point
  double _polarAngle(LatLng pivot, LatLng point) {
    final dx = point.longitude - pivot.longitude;
    final dy = point.latitude - pivot.latitude;
    return math.atan2(dy, dx);
  }
  
  /// Calculate squared distance between two points (faster than actual distance)
  double _distance(LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    return dx * dx + dy * dy;
  }
  
  /// Calculate cross product to determine turn direction
  /// Positive = counter-clockwise, Negative = clockwise, Zero = collinear
  double _crossProduct(LatLng a, LatLng b, LatLng c) {
    return (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
  }
  
  /// Reserved for future cache usage.
  void clearCache() {}
}
