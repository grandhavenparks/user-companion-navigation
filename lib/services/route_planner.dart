import 'dart:math' as math;

import '../utils/distance_calculator.dart';

/// A point the planner can route through.
class PlanPoint {
  const PlanPoint(this.id, this.latitude, this.longitude);

  final String id;
  final double latitude;
  final double longitude;
}

/// Picks the point to navigate to next.
///
/// The nearest point wins, except that an existing target is kept until
/// another point is closer by a clear margin. That way the target follows the
/// user when they wander off without marking a point visited, but does not
/// flicker between two points that are about equally far away.
PlanPoint? chooseTarget({
  required double latitude,
  required double longitude,
  required List<PlanPoint> candidates,
  String? currentTargetId,
  double gpsAccuracyMeters = 0,
  double minSwitchMeters = 5,
  double switchFraction = 0.2,
}) {
  if (candidates.isEmpty) return null;

  PlanPoint? nearest;
  var nearestDistance = double.infinity;
  PlanPoint? current;
  var currentDistance = double.infinity;

  for (final point in candidates) {
    final d = calculateDistance(latitude, longitude, point.latitude, point.longitude);
    if (d < nearestDistance) {
      nearest = point;
      nearestDistance = d;
    }
    if (point.id == currentTargetId) {
      current = point;
      currentDistance = d;
    }
  }

  if (current == null || identical(current, nearest)) return nearest;

  final margin = math.max(
    minSwitchMeters,
    math.max(switchFraction * currentDistance, gpsAccuracyMeters / 2),
  );
  return nearestDistance < currentDistance - margin ? nearest : current;
}

/// Orders [points] into an open route that starts at [start] (which is not
/// part of [points]) and ends at whichever point is visited last.
///
/// Nearest-neighbour construction followed by 2-opt improvement with the
/// start fixed and the end free. Distances use a local equirectangular
/// projection, which is accurate at park scale.
List<PlanPoint> orderOpenRoute(
  PlanPoint start,
  List<PlanPoint> points, {
  int maxRefinePoints = 600,
  int maxPasses = 8,
}) {
  final n = points.length;
  if (n <= 1) return List<PlanPoint>.of(points);

  final lat0 = start.latitude * math.pi / 180;
  final cosLat = math.cos(lat0);
  double x(PlanPoint p) => (p.longitude - start.longitude) * 111320.0 * cosLat;
  double y(PlanPoint p) => (p.latitude - start.latitude) * 110574.0;

  final px = List<double>.generate(n, (i) => x(points[i]));
  final py = List<double>.generate(n, (i) => y(points[i]));

  // Nearest neighbour from the start.
  final used = List<bool>.filled(n, false);
  final order = <int>[];
  var cx = 0.0;
  var cy = 0.0;
  for (var step = 0; step < n; step++) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < n; i++) {
      if (used[i]) continue;
      final dx = px[i] - cx;
      final dy = py[i] - cy;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    used[best] = true;
    order.add(best);
    cx = px[best];
    cy = py[best];
  }

  if (n <= maxRefinePoints) {
    // Path nodes: 0 = start, 1..n = order[0..n-1].
    final nodeX = <double>[0, ...order.map((i) => px[i])];
    final nodeY = <double>[0, ...order.map((i) => py[i])];
    final nodeIndex = <int>[-1, ...order];
    double dist(int a, int b) {
      final dx = nodeX[a] - nodeX[b];
      final dy = nodeY[a] - nodeY[b];
      return math.sqrt(dx * dx + dy * dy);
    }

    void reverse(int i, int j) {
      while (i < j) {
        final tx = nodeX[i];
        final ty = nodeY[i];
        final ti = nodeIndex[i];
        nodeX[i] = nodeX[j];
        nodeY[i] = nodeY[j];
        nodeIndex[i] = nodeIndex[j];
        nodeX[j] = tx;
        nodeY[j] = ty;
        nodeIndex[j] = ti;
        i++;
        j--;
      }
    }

    for (var pass = 0; pass < maxPasses; pass++) {
      var improved = false;
      for (var i = 1; i < n; i++) {
        for (var j = i + 1; j <= n; j++) {
          // Reverse nodes i..j: edges (i-1,i) and (j,j+1) are replaced by
          // (i-1,j) and (i,j+1). When j is the last node there is no (j,j+1).
          var delta = dist(i - 1, j) - dist(i - 1, i);
          if (j < n) delta += dist(i, j + 1) - dist(j, j + 1);
          if (delta < -1e-6) {
            reverse(i, j);
            improved = true;
          }
        }
      }
      if (!improved) break;
    }
    order
      ..clear()
      ..addAll(nodeIndex.skip(1));
  }

  return [for (final i in order) points[i]];
}

/// Length in metres of the path start -> points[0] -> points[1] -> ...
double routeLength(PlanPoint start, List<PlanPoint> points) {
  var total = 0.0;
  var prev = start;
  for (final p in points) {
    total += calculateDistance(prev.latitude, prev.longitude, p.latitude, p.longitude);
    prev = p;
  }
  return total;
}
