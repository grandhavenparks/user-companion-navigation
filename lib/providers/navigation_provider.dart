import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/tree.dart';
import '../models/user_location.dart';
import '../services/route_planner.dart';
import '../utils/bearing_calculator.dart';
import '../utils/distance_calculator.dart';
import 'location_provider.dart';
import 'park_provider.dart';
import 'run_provider.dart';
import 'settings_provider.dart';

enum NavigationPhase {
  /// No park selected.
  noPark,

  /// Waiting for the first GPS fix.
  waitingForLocation,

  /// The user is not inside any area of the selected park.
  outsidePark,

  /// The user's area has no imported points.
  noPoints,

  /// Every point in the user's area is marked visited.
  allVisited,

  /// Guiding the user to [NavigationState.target].
  navigating,
}

@immutable
class NavigationState {
  const NavigationState({
    required this.phase,
    this.areaIndex,
    this.target,
    this.targetDistance,
    this.targetBearing,
    this.arrived = false,
    this.upcoming = const [],
    this.remainingDistance = 0,
    this.visitedInArea = 0,
    this.totalInArea = 0,
  });

  final NavigationPhase phase;

  /// Park area the user is in.
  final int? areaIndex;

  /// Point to walk to now (nearest unvisited point, with hysteresis).
  final Tree? target;
  final double? targetDistance;
  final double? targetBearing;

  /// Within the arrival radius of [target].
  final bool arrived;

  /// Unvisited points after [target], in visiting order. The route is open:
  /// it ends at the last of these points.
  final List<Tree> upcoming;

  /// Straight-line distance user -> target -> upcoming...
  final double remainingDistance;
  final int visitedInArea;
  final int totalInArea;

  bool get isActive => phase == NavigationPhase.navigating;

  /// target followed by the upcoming points, for drawing the route.
  List<LatLng> get routeAfterUser => [
        if (target != null) target!.position,
        ...upcoming.map((t) => t.position),
      ];
}

/// Remembers the current target and route order between GPS fixes, so the
/// target only changes for a clear reason and the route is not recomputed on
/// every update.
class NavigationMemory {
  String? targetId;
  String orderKey = '';
  List<String> orderIds = const [];
  double legsLength = 0;

  void reset() {
    targetId = null;
    orderKey = '';
    orderIds = const [];
    legsLength = 0;
  }
}

/// One memory per view, so switching between points and clusters keeps each
/// view's target and route order.
class NavigationMemories {
  final NavigationMemory points = NavigationMemory();
  final NavigationMemory clusters = NavigationMemory();
}

final _navigationMemoriesProvider =
    Provider.autoDispose<NavigationMemories>((ref) => NavigationMemories());

/// Recomputed on every GPS fix, every change to the visible points (import,
/// run switch, view switch, mark visited) and when the park or arrival radius
/// changes. Points and clusters are navigated the same way; only the arrival
/// radius differs.
final navigationProvider = Provider.autoDispose<NavigationState>((ref) {
  final memories = ref.watch(_navigationMemoriesProvider);
  final clusterView = ref.watch(clusterViewProvider);
  final parkTrees = ref.watch(parkTreesProvider);
  final location =
      ref.watch(locationControllerProvider.select((s) => s.location));
  final arrivalRadius = ref.watch(settingsProvider.select((s) => clusterView
      ? s.clusterArrivalRadiusMeters
      : s.arrivalRadiusMeters));
  final memory = clusterView ? memories.clusters : memories.points;
  return computeNavigation(
    memory: memory,
    parkTrees: parkTrees,
    location: location,
    arrivalRadiusMeters: arrivalRadius,
  );
});

/// Pure navigation step (unit tested).
NavigationState computeNavigation({
  required NavigationMemory memory,
  required ParkTrees parkTrees,
  required UserLocation? location,
  required double arrivalRadiusMeters,
}) {
  final park = parkTrees.park;
  if (park == null) {
    memory.reset();
    return const NavigationState(phase: NavigationPhase.noPark);
  }
  if (location == null) {
    return const NavigationState(phase: NavigationPhase.waitingForLocation);
  }

  final area = park.areaIndexAt(location.latitude, location.longitude);
  if (area == null) {
    memory.reset();
    return const NavigationState(phase: NavigationPhase.outsidePark);
  }

  final areaTrees = parkTrees.inArea(area);
  final unvisited = areaTrees.where((t) => !t.visited).toList();
  final visitedCount = areaTrees.length - unvisited.length;
  if (areaTrees.isEmpty) {
    memory.reset();
    return NavigationState(phase: NavigationPhase.noPoints, areaIndex: area);
  }
  if (unvisited.isEmpty) {
    memory.reset();
    return NavigationState(
      phase: NavigationPhase.allVisited,
      areaIndex: area,
      visitedInArea: visitedCount,
      totalInArea: areaTrees.length,
    );
  }

  final byId = {for (final t in unvisited) t.id: t};
  final candidates = [
    for (final t in unvisited) PlanPoint(t.id, t.latitude, t.longitude),
  ];
  final targetPoint = chooseTarget(
    latitude: location.latitude,
    longitude: location.longitude,
    candidates: candidates,
    currentTargetId: memory.targetId,
    gpsAccuracyMeters: location.accuracy ?? 0,
    minSwitchMeters: AppConfig.targetSwitchMinMeters,
    switchFraction: AppConfig.targetSwitchFraction,
  )!;
  memory.targetId = targetPoint.id;

  // Re-order the rest only when the target or the set of points changed.
  final key = '${targetPoint.id}|${unvisited.length}|'
      '${Object.hashAllUnordered(unvisited.map((t) => t.id))}';
  if (key != memory.orderKey) {
    final rest = candidates.where((c) => c.id != targetPoint.id).toList();
    final ordered = orderOpenRoute(
      targetPoint,
      rest,
      maxRefinePoints: AppConfig.maxPointsForRouteRefinement,
    );
    memory
      ..orderKey = key
      ..orderIds = [for (final p in ordered) p.id]
      ..legsLength = routeLength(targetPoint, ordered);
  }

  final target = byId[targetPoint.id]!;
  final distance = calculateDistance(
      location.latitude, location.longitude, target.latitude, target.longitude);
  final bearing = calculateBearing(
      location.latitude, location.longitude, target.latitude, target.longitude);

  return NavigationState(
    phase: NavigationPhase.navigating,
    areaIndex: area,
    target: target,
    targetDistance: distance,
    targetBearing: bearing,
    arrived: distance <= arrivalRadiusMeters,
    upcoming: [
      for (final id in memory.orderIds)
        if (byId[id] != null) byId[id]!,
    ],
    remainingDistance: distance + memory.legsLength,
    visitedInArea: visitedCount,
    totalInArea: areaTrees.length,
  );
}
