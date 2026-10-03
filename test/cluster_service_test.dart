import 'dart:math' as math;

import 'package:user_navigation_companion/models/dataset.dart';
import 'package:user_navigation_companion/models/tree.dart';
import 'package:user_navigation_companion/providers/park_provider.dart';
import 'package:user_navigation_companion/services/cluster_service.dart';
import 'package:user_navigation_companion/services/park_service.dart';
import 'package:flutter_test/flutter_test.dart';

const double lat = 43.05;
final double dLat = 100 / 111320.0;

/// Latitude in the middle of the grid row that contains [lat]. All test
/// points use it, so it is also the mean latitude the grid is sized from.
final double rowLat = ((lat / dLat).floor() + 0.5) * dLat;
final double dLon = 100 / (111320.0 * math.cos(rowLat * math.pi / 180));

/// Longitude at [fraction] of grid cell column [cx] (same grid as the app).
double lonIn(int cx, double fraction) => (cx + fraction) * dLon;

Tree point(String name, double lon,
        {String? classification, bool visited = false, double? latitude}) =>
    Tree(
      id: name,
      datasetId: 'run',
      filename: name,
      latitude: latitude ?? rowLat,
      longitude: lon,
      classification: classification,
      visited: visited,
      predictionScore: 99.0,
    );

void main() {
  final cx = (-86.2350 / dLon).floor();

  test('points in one 100 m cell merge at their average position', () {
    final clusters = clusterPoints(
      [
        point('a', lonIn(cx, 0.2), classification: 'OAK WILT'),
        point('b', lonIn(cx, 0.6), classification: 'OAK WILT'),
        point('c', lonIn(cx, 0.9), classification: 'HEALTHY'),
        point('d', lonIn(cx + 2, 0.5)),
      ],
      parks: const [],
      datasetId: 'set',
    );
    expect(clusters, hasLength(2));
    final big = clusters.first;
    expect(big.memberCount, 3);
    expect(big.members, ['a', 'b', 'c']);
    expect(big.longitude, closeTo(lonIn(cx, (0.2 + 0.6 + 0.9) / 3), 1e-9));
    expect(big.latitude, closeTo(rowLat, 1e-12));
    expect(big.classification, 'OAK WILT');
    expect(big.filename, 'Cluster 1 (3 trees)');
    expect(big.predictionScore, isNull, reason: 'clusters have no confidence');
    expect(big.datasetId, 'set');
    expect(big.isCluster, isTrue);
    expect(clusters[1].filename, 'Cluster 2 (1 tree)');
  });

  test('new clusters are unvisited even when their points were visited', () {
    final clusters = clusterPoints(
      [
        point('a', lonIn(cx, 0.3), visited: true),
        point('b', lonIn(cx, 0.7), visited: true),
      ],
      parks: const [],
      datasetId: 'set',
    );
    expect(clusters.single.visited, isFalse);
  });

  test('a cell is never shared by two park areas; the area is remembered', () {
    // Two park areas side by side, split in the middle of grid column cx.
    final split = lonIn(cx, 0.5);
    final south = rowLat - 0.001;
    final north = rowLat + 0.001;
    String rect(double west, double east) =>
        '[[[$west,$south],[$east,$south],[$east,$north],[$west,$north],[$west,$south]]]';
    final park = parseParkGeoJson(
      '{"type":"MultiPolygon","coordinates":['
      '${rect(lonIn(cx, -1), split)},${rect(split, lonIn(cx, 2))}]}',
      fileName: 'MI_0001_Test.geojson',
    );
    final clusters = clusterPoints(
      [point('west', lonIn(cx, 0.25)), point('east', lonIn(cx, 0.75))],
      parks: [park],
      datasetId: 'set',
    );
    expect(clusters, hasLength(2));
    final byName = {for (final c in clusters) c.members.single: c};
    expect(byName['west']!.areaIndex, 0);
    expect(byName['east']!.areaIndex, 1);
    expect(byName['west']!.parkId, park.id);
  });

  test('a cluster just outside the boundary still belongs to its area', () {
    final park = parseParkGeoJson(
      '{"type":"Polygon","coordinates":[[[-86.24,43.04],[-86.23,43.04],'
      '[-86.23,43.05],[-86.24,43.05],[-86.24,43.04]]]}',
      fileName: 'MI_0002_Box.geojson',
    );
    const outsideCluster = Tree(
      id: 'c1',
      datasetId: 'set',
      filename: 'Cluster 1 (2 trees)',
      latitude: 43.0501,
      longitude: -86.235,
      memberCount: 2,
      parkId: 'MI_0002_Box',
      areaIndex: 0,
    );
    const outsidePoint = Tree(
      id: 'p1',
      datasetId: 'run',
      filename: 'IMG_1.jpg',
      latitude: 43.0501,
      longitude: -86.235,
    );
    final pt = buildParkTrees(park, const [outsideCluster, outsidePoint]);
    expect(pt.isInPark(outsideCluster), isTrue);
    expect(pt.isInPark(outsidePoint), isFalse);
  });

  test('createClusterSet makes a cluster dataset of the run', () {
    const run = Dataset(id: 'run1', name: 'oak_wilt_results', treeCount: 2);
    final set = createClusterSet(
      run,
      [point('a', lonIn(cx, 0.3)), point('b', lonIn(cx, 0.6))],
      parks: const [],
    );
    expect(set.dataset.kind, DatasetKind.clusters);
    expect(set.dataset.parentId, 'run1');
    expect(set.dataset.treeCount, 1);
    expect(set.clusters.single.datasetId, set.dataset.id);
  });

  test('most common classification, ties go to the first seen', () {
    expect(mostCommon(['A', 'B', 'B', null, '']), 'B');
    expect(mostCommon(['A', 'B']), 'A');
    expect(mostCommon([null, ' ']), isNull);
  });
}
