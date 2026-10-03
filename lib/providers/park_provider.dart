import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/park.dart';
import '../models/tree.dart';
import '../services/park_service.dart';
import 'trees_provider.dart';

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

/// Enabled points split by the selected park's areas.
@immutable
class ParkTrees {
  const ParkTrees({
    required this.park,
    required this.all,
    required this.areaOf,
  });

  final Park? park;

  /// Every point from enabled datasets (inside and outside the park).
  final List<Tree> all;

  /// Point id -> index of the park area containing it. Points outside the
  /// park are not in this map.
  final Map<String, int> areaOf;

  bool isInPark(Tree tree) => areaOf.containsKey(tree.id);

  List<Tree> inArea(int areaIndex) =>
      all.where((t) => areaOf[t.id] == areaIndex).toList();

  int get insideCount => areaOf.length;
  int get outsideCount => all.length - areaOf.length;
}

final parkTreesProvider = Provider.autoDispose<ParkTrees>((ref) {
  final park = ref.watch(selectedParkProvider);
  final trees = ref.watch(enabledTreesProvider).valueOrNull ?? const <Tree>[];
  final areaOf = <String, int>{};
  if (park != null) {
    for (final tree in trees) {
      final area = park.areaIndexAt(tree.latitude, tree.longitude);
      if (area != null) areaOf[tree.id] = area;
    }
  }
  return ParkTrees(park: park, all: trees, areaOf: areaOf);
});

/// Which park (and area) a point belongs to, if any.
class ParkMembership {
  const ParkMembership(this.park, this.areaIndex);

  final Park park;
  final int areaIndex;
}

ParkMembership? findParkMembership(List<Park> parks, double lat, double lng) {
  for (final park in parks) {
    final area = park.areaIndexAt(lat, lng);
    if (area != null) return ParkMembership(park, area);
  }
  return null;
}
