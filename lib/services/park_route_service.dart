import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/tree.dart';
import '../models/user_location.dart';
import '../utils/distance_calculator.dart';

/// Represents a closed-loop route through trees in a park
class ParkRoute {
  const ParkRoute({
    required this.trees,
    required this.pathPoints,
    required this.totalDistance,
  });

  final List<Tree> trees; // Trees in visiting order (closed loop)
  final List<LatLng> pathPoints; // Path including return to start
  final double totalDistance; // Total loop distance in meters

  /// Get the next tree to visit based on current location
  Tree? getNextTree(UserLocation userLocation) {
    if (trees.isEmpty) return null;

    // Find first unvisited tree in the loop
    for (final tree in trees) {
      if (!tree.visited) {
        return tree;
      }
    }

    return null; // All trees visited
  }

  /// Calculate distance along path to a specific tree
  double getDistanceToTree(Tree tree) {
    final treeIndex = trees.indexWhere((t) => t.id == tree.id);
    if (treeIndex == -1) return 0;

    double distance = 0;
    for (int i = 0; i <= treeIndex && i < pathPoints.length - 1; i++) {
      distance += calculateDistance(
        pathPoints[i].latitude,
        pathPoints[i].longitude,
        pathPoints[i + 1].latitude,
        pathPoints[i + 1].longitude,
      );
    }
    return distance;
  }
}

/// Service for creating closed-loop routes through trees
class ParkRouteService {
  ParkRouteService._();

  /// Create a closed-loop route through trees using nearest neighbor
  /// Starting from user location, connecting each tree to its nearest unvisited neighbor
  static ParkRoute createClosedLoop({
    required UserLocation startLocation,
    required List<Tree> trees,
  }) {
    if (trees.isEmpty) {
      return ParkRoute(
        trees: [],
        pathPoints: [LatLng(startLocation.latitude, startLocation.longitude)],
        totalDistance: 0,
      );
    }

    final unvisitedTrees = List<Tree>.from(trees);
    final route = <Tree>[];
    final pathPoints = <LatLng>[
      LatLng(startLocation.latitude, startLocation.longitude),
    ];

    double totalDistance = 0;
    double currentLat = startLocation.latitude;
    double currentLng = startLocation.longitude;

    // Build route using nearest neighbor
    while (unvisitedTrees.isNotEmpty) {
      Tree? nearest;
      double nearestDistance = double.infinity;

      for (final tree in unvisitedTrees) {
        final distance = calculateDistance(
          currentLat,
          currentLng,
          tree.latitude,
          tree.longitude,
        );

        if (distance < nearestDistance) {
          nearest = tree;
          nearestDistance = distance;
        }
      }

      if (nearest != null) {
        route.add(nearest);
        pathPoints.add(LatLng(nearest.latitude, nearest.longitude));
        totalDistance += nearestDistance;
        currentLat = nearest.latitude;
        currentLng = nearest.longitude;
        unvisitedTrees.remove(nearest);
      }
    }

    // Close the loop: return to start location
    if (route.isNotEmpty) {
      final returnDistance = calculateDistance(
        currentLat,
        currentLng,
        startLocation.latitude,
        startLocation.longitude,
      );
      totalDistance += returnDistance;
      pathPoints.add(LatLng(startLocation.latitude, startLocation.longitude));
    }

    return ParkRoute(
      trees: route,
      pathPoints: pathPoints,
      totalDistance: totalDistance,
    );
  }

  /// Calculate bearing from one point to another (0-360 degrees from North)
  static double calculateBearing({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    const double pi = 3.14159265359;
    final lat1 = fromLat * (pi / 180.0);
    final lat2 = toLat * (pi / 180.0);
    final dLng = (toLng - fromLng) * (pi / 180.0);

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final bearing = math.atan2(y, x) * (180.0 / pi);
    return (bearing + 360) % 360;
  }
}
