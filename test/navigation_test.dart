import 'package:edge_forestry_mobile/models/tree.dart';
import 'package:edge_forestry_mobile/models/user_location.dart';
import 'package:edge_forestry_mobile/providers/navigation_provider.dart';
import 'package:edge_forestry_mobile/providers/park_provider.dart';
import 'package:edge_forestry_mobile/services/park_service.dart';
import 'package:flutter_test/flutter_test.dart';

Tree _tree(String id, double lat, double lng, {bool visited = false}) => Tree(
      id: id,
      datasetId: 'd',
      filename: id,
      latitude: lat,
      longitude: lng,
      visited: visited,
    );

UserLocation _at(double lat, double lng) => UserLocation(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026),
      accuracy: 4,
    );

void main() {
  final park = parseParkGeoJson(
    '{"type":"Polygon","coordinates":[[[-93.04,45.34],[-93.02,45.34],'
    '[-93.02,45.36],[-93.04,45.36],[-93.04,45.34]]]}',
    fileName: 'MN_0001_Test.geojson',
  );

  ParkTrees treesFor(List<Tree> trees) {
    final areaOf = <String, int>{};
    for (final t in trees) {
      final a = park.areaIndexAt(t.latitude, t.longitude);
      if (a != null) areaOf[t.id] = a;
    }
    return ParkTrees(park: park, all: trees, areaOf: areaOf);
  }

  final trees = [
    _tree('near', 45.3500, -93.0300),
    _tree('far', 45.3580, -93.0250),
    _tree('outside', 45.4000, -93.5000),
  ];

  test('outside the park: no navigation', () {
    final s = computeNavigation(
      memory: NavigationMemory(),
      parkTrees: treesFor(trees),
      location: _at(45.30, -93.03),
      arrivalRadiusMeters: 10,
    );
    expect(s.phase, NavigationPhase.outsidePark);
  });

  test('targets the nearest point; outside points never join the route', () {
    final s = computeNavigation(
      memory: NavigationMemory(),
      parkTrees: treesFor(trees),
      location: _at(45.3490, -93.0300),
      arrivalRadiusMeters: 10,
    );
    expect(s.phase, NavigationPhase.navigating);
    expect(s.target!.id, 'near');
    expect(s.upcoming.map((t) => t.id), ['far']);
    expect(s.totalInArea, 2);
    expect(s.arrived, isFalse);
  });

  test('arrived within the radius', () {
    final s = computeNavigation(
      memory: NavigationMemory(),
      parkTrees: treesFor(trees),
      location: _at(45.35003, -93.0300),
      arrivalRadiusMeters: 10,
    );
    expect(s.arrived, isTrue);
  });

  test('wandering off without marking switches to the nearest tree', () {
    final memory = NavigationMemory();
    final pt = treesFor(trees);
    computeNavigation(
        memory: memory, parkTrees: pt, location: _at(45.3490, -93.03), arrivalRadiusMeters: 10);
    expect(memory.targetId, 'near');
    final s = computeNavigation(
        memory: memory, parkTrees: pt, location: _at(45.3578, -93.0252), arrivalRadiusMeters: 10);
    expect(s.target!.id, 'far');
    expect(s.upcoming.map((t) => t.id), ['near']);
  });

  test('all visited', () {
    final s = computeNavigation(
      memory: NavigationMemory(),
      parkTrees: treesFor([
        _tree('near', 45.35, -93.03, visited: true),
      ]),
      location: _at(45.349, -93.03),
      arrivalRadiusMeters: 10,
    );
    expect(s.phase, NavigationPhase.allVisited);
    expect(s.totalInArea, 1);
  });
}
