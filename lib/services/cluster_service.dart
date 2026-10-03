import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../models/park.dart';
import '../models/tree.dart';

/// A cluster dataset plus its points, ready to be saved.
class ClusterSet {
  const ClusterSet({required this.dataset, required this.clusters});

  final Dataset dataset;
  final List<Tree> clusters;
}

/// Builds a fresh cluster set for [run] from its [points].
///
/// Works like an import made on the spot: a new dataset (kind = clusters,
/// parent = run) whose points are the clusters, all unvisited.
ClusterSet createClusterSet(
  Dataset run,
  List<Tree> points, {
  required List<Park> parks,
  double cellMeters = AppConfig.clusterCellMeters,
  DateTime? now,
}) {
  final datasetId = const Uuid().v4();
  final clusters = clusterPoints(
    points,
    parks: parks,
    datasetId: datasetId,
    cellMeters: cellMeters,
  );
  return ClusterSet(
    dataset: Dataset(
      id: datasetId,
      name: '${run.name} · clusters',
      treeCount: clusters.length,
      importedAt: now ?? DateTime.now(),
      kind: DatasetKind.clusters,
      parentId: run.id,
    ),
    clusters: clusters,
  );
}

/// Condenses [points] on a [cellMeters] grid, exactly like the old app:
///
/// * cell = floor(lat / cellHeight), floor(lon / cellWidth), with the grid
///   fixed to latitude/longitude lines; the longitude cell width uses the
///   mean latitude of all points so cells are roughly square on the ground;
/// * every point in a cell is merged regardless of classification or
///   visited state;
/// * the cluster sits at the average position of its members;
/// * its classification is the most common one among the members.
///
/// Additionally a cluster never mixes points from different park areas (or
/// inside/outside a park), and remembers that area so it is still navigated
/// when its average position falls just outside the boundary.
///
/// New clusters are always unvisited. Largest clusters come first.
List<Tree> clusterPoints(
  List<Tree> points, {
  required List<Park> parks,
  required String datasetId,
  double cellMeters = AppConfig.clusterCellMeters,
}) {
  if (points.isEmpty) return const [];

  final meanLat =
      points.map((t) => t.latitude).reduce((a, b) => a + b) / points.length;
  final dLat = cellMeters / 111320.0;
  final cosLat = math.cos(meanLat * math.pi / 180.0);
  final dLon =
      cellMeters / (111320.0 * (cosLat.abs() < 1e-6 ? 1e-6 : cosLat));

  final groups = <String, _Group>{};
  for (final t in points) {
    final cy = (t.latitude / dLat).floor();
    final cx = (t.longitude / dLon).floor();
    final membership = findParkMembership(parks, t.latitude, t.longitude);
    final where = membership == null
        ? '-'
        : '${membership.park.id}#${membership.areaIndex}';
    groups.putIfAbsent('$cx:$cy|$where', () => _Group(membership)).add(t);
  }

  final built = <_Built>[];
  for (final group in groups.values) {
    final members = group.members;
    final n = members.length;
    final lat = members.map((t) => t.latitude).reduce((a, b) => a + b) / n;
    final lon = members.map((t) => t.longitude).reduce((a, b) => a + b) / n;
    built.add(_Built(
      latitude: lat,
      longitude: lon,
      count: n,
      classification: mostCommon(members.map((t) => t.classification)),
      members: [for (final t in members) t.filename],
      membership: group.membership,
    ));
  }

  // Largest clusters first (same order as the old app).
  built.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.latitude.compareTo(b.latitude);
  });

  const uuid = Uuid();
  return [
    for (var i = 0; i < built.length; i++)
      Tree(
        id: uuid.v4(),
        datasetId: datasetId,
        filename: clusterName(i + 1, built[i].count),
        latitude: built[i].latitude,
        longitude: built[i].longitude,
        classification: built[i].classification,
        memberCount: built[i].count,
        members: built[i].members,
        parkId: built[i].membership?.park.id,
        areaIndex: built[i].membership?.areaIndex,
      ),
  ];
}

/// "Cluster 3 (5 trees)"; "Cluster 3" when the size is unknown (0).
String clusterName(int number, int count) {
  if (count <= 0) return 'Cluster $number';
  return 'Cluster $number ($count ${count == 1 ? 'tree' : 'trees'})';
}

/// Most common non-empty value; ties go to the value seen first.
String? mostCommon(Iterable<String?> values) {
  final counts = <String, int>{};
  for (final v in values) {
    final s = v?.trim();
    if (s != null && s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
  }
  String? best;
  var bestN = -1;
  counts.forEach((value, n) {
    if (n > bestN) {
      bestN = n;
      best = value;
    }
  });
  return best;
}

class _Group {
  _Group(this.membership);

  final ParkMembership? membership;
  final List<Tree> members = [];

  void add(Tree t) => members.add(t);
}

class _Built {
  const _Built({
    required this.latitude,
    required this.longitude,
    required this.count,
    required this.classification,
    required this.members,
    required this.membership,
  });

  final double latitude;
  final double longitude;
  final int count;
  final String? classification;
  final List<String> members;
  final ParkMembership? membership;
}
