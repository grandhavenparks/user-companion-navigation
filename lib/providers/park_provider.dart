import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/park.dart';
import '../models/tree.dart';
import '../services/park_service.dart';
import '../services/park_route_service.dart';
import '../services/points_service.dart';
import 'trees_provider.dart';
import 'location_provider.dart';

/// Provider for all available parks
final parksProvider = FutureProvider<List<Park>>((ref) async {
  return await ParkService.instance.loadParks();
});

/// Provider for the currently selected park
final selectedParkProvider = StateProvider<Park?>((ref) => null);

/// Provider for trees within the selected park
final parkTreesProvider = Provider<List<Tree>>((ref) {
  final selectedPark = ref.watch(selectedParkProvider);
  final treesAsync = ref.watch(enabledTreesProvider);

  return treesAsync.when(
    data: (trees) {
      if (selectedPark == null) return [];

      // Filter trees within park boundary
      return trees.where((tree) {
        return selectedPark.containsPoint(tree.latitude, tree.longitude);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Provider for the park route (closed loop)
final parkRouteProvider = Provider<ParkRoute?>((ref) {
  final selectedPark = ref.watch(selectedParkProvider);
  final parkTrees = ref.watch(parkTreesProvider);
  final locationAsync = ref.watch(locationStreamProvider);

  if (selectedPark == null || parkTrees.isEmpty) {
    return null;
  }

  return locationAsync.when(
    data: (location) {
      if (location == null) return null;

      // Create closed-loop route through unvisited trees
      final unvisitedTrees = parkTrees.where((t) => !t.visited).toList();
      if (unvisitedTrees.isEmpty) return null;

      return ParkRouteService.createClosedLoop(
        startLocation: location,
        trees: unvisitedTrees,
      );
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Provider for the next tree to visit in the route
final nextTreeProvider = Provider<Tree?>((ref) {
  final selectedPark = ref.watch(selectedParkProvider);
  final route = ref.watch(parkRouteProvider);
  final locationAsync = ref.watch(locationStreamProvider);

  if (selectedPark == null || route == null) return null;

  return locationAsync.when(
    data: (location) {
      if (location == null) return null;
      final nextTree = route.getNextTree(location);
      
      // Double-check that next tree is within the selected park
      if (nextTree != null && 
          !selectedPark.containsPoint(nextTree.latitude, nextTree.longitude)) {
        return null; // Tree is outside park, don't show it
      }
      
      return nextTree;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});
/// Closed-loop polygon around all enabled imported points that lie inside the park boundary.
///
/// Uses [ref.watch] on [enabledTreesProvider] so the polygon updates immediately after CSV import.
final parkPointsProvider = Provider.family<List<LatLng>, String>((ref, parkId) {
  final parksAsync = ref.watch(parksProvider);
  final treesAsync = ref.watch(enabledTreesProvider);

  return parksAsync.when(
    data: (parks) {
      Park? park;
      for (final p in parks) {
        if (p.id == parkId) {
          park = p;
          break;
        }
      }
      if (park == null) return [];

      return treesAsync.when(
        data: (trees) {
          final points = trees
              .where((t) => park!.containsPoint(t.latitude, t.longitude))
              .map((t) => ParkPoint(latitude: t.latitude, longitude: t.longitude))
              .toList();
          if (points.isEmpty) return [];
          return PointsService.instance.createClosedLoop(points);
        },
        loading: () => [],
        error: (_, __) => [],
      );
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

