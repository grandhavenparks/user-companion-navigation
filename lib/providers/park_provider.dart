import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/park.dart';
import '../models/tree.dart';
import '../services/park_service.dart';
import 'run_provider.dart';

export '../models/park.dart' show ParkMembership, findParkMembership;

/// All parks bundled under `parks/` (plus files that failed to load).
final parksProvider = FutureProvider<ParkLoadResult>((ref) {
  return ParkService.instance.loadParks();
});

/// Id of the park shown on the map; remembered while the app runs.
final selectedParkIdProvider = StateProvider<String?>((ref) => null);

final selectedParkProvider = Provider<Park?>((ref) {
  final id = ref.watch(selectedParkIdProvider);
  if (id == null) return null;
  final parks = ref.watch(parksProvider).valueOrNull?.parks ?? const <Park>[];
  for (final park in parks) {
    if (park.id == id) return park;
  }
  return null;
});

/// The visible points (active run's points or clusters) split by the
/// selected park's areas.
@immutable
class ParkTrees {
  const ParkTrees({
    required this.park,
    required this.all,
    required this.areaOf,
  });

  final Park? park;

  /// Every visible point (inside and outside the park).
  final List<Tree> all;

  /// Point id -> index of the park area it belongs to. Points outside the
  /// park are not in this map.
  final Map<String, int> areaOf;

  bool isInPark(Tree tree) => areaOf.containsKey(tree.id);

  List<Tree> inArea(int areaIndex) =>
      all.where((t) => areaOf[t.id] == areaIndex).toList();

  int get insideCount => areaOf.length;
  int get outsideCount => all.length - areaOf.length;
}

/// Area of [park] that [tree] belongs to: where it lies, or for a cluster
/// whose average position fell just outside, the area of its members.
int? areaOfPoint(Park park, Tree tree) {
  final area = park.areaIndexAt(tree.latitude, tree.longitude);
  if (area != null) return area;
  final stored = tree.areaIndex;
  if (tree.parkId == park.id && stored != null && stored < park.areas.length) {
    return stored;
  }
  return null;
}

ParkTrees buildParkTrees(Park? park, List<Tree> points) {
  final areaOf = <String, int>{};
  if (park != null) {
    for (final tree in points) {
      final area = areaOfPoint(park, tree);
      if (area != null) areaOf[tree.id] = area;
    }
  }
  return ParkTrees(park: park, all: points, areaOf: areaOf);
}

final parkTreesProvider = Provider.autoDispose<ParkTrees>((ref) {
  final park = ref.watch(selectedParkProvider);
  final points = ref.watch(visiblePointsProvider);
  return buildParkTrees(park, points);
});

/// Number of visible points (the active run's points, or its clusters in
/// cluster view) per park id. Shown in the park list.
final visibleParkCountsProvider = Provider<Map<String, int>>((ref) {
  final parks = ref.watch(parksProvider).valueOrNull?.parks ?? const <Park>[];
  final points = ref.watch(visiblePointsProvider);
  final counts = <String, int>{};
  for (final t in points) {
    final m = membershipOf(parks, t);
    if (m != null) counts[m.park.id] = (counts[m.park.id] ?? 0) + 1;
  }
  return counts;
});

/// Park/area a point belongs to (by position, or a cluster's stored area).
ParkMembership? membershipOf(List<Park> parks, Tree tree) {
  final byPosition = findParkMembership(parks, tree.latitude, tree.longitude);
  if (byPosition != null) return byPosition;
  for (final park in parks) {
    final area = areaOfPoint(park, tree);
    if (area != null) return ParkMembership(park, area);
  }
  return null;
}
