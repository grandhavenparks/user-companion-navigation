import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import '../models/tree.dart';
import 'dataset_provider.dart';
import 'settings_provider.dart';
import 'trees_provider.dart';

/// All imported runs (CSV files), newest first.
final runsProvider = Provider<List<Dataset>>((ref) {
  final all = ref.watch(datasetsProvider).valueOrNull ?? const <Dataset>[];
  return [for (final d in all) if (d.isRun) d];
});

/// The one run used on the map. Runs are never shown together; when no run
/// was chosen (or it was deleted) the most recently imported run is used.
final activeRunProvider = Provider<Dataset?>((ref) {
  final runs = ref.watch(runsProvider);
  if (runs.isEmpty) return null;
  final id = ref.watch(settingsProvider.select((s) => s.activeRunId));
  for (final run in runs) {
    if (run.id == id) return run;
  }
  return runs.first;
});

/// Cluster set of [runId], if one was created or imported.
Dataset? clusterSetOf(List<Dataset> datasets, String runId) {
  for (final d in datasets) {
    if (d.isClusterSet && d.parentId == runId) return d;
  }
  return null;
}

/// Cluster set of the active run.
final activeClusterSetProvider = Provider<Dataset?>((ref) {
  final run = ref.watch(activeRunProvider);
  if (run == null) return null;
  final all = ref.watch(datasetsProvider).valueOrNull ?? const <Dataset>[];
  return clusterSetOf(all, run.id);
});

/// Map shows clusters instead of points (remembered across restarts).
final clusterViewProvider =
    Provider<bool>((ref) => ref.watch(settingsProvider.select((s) => s.clusterView)));

/// Points of the active run.
final runPointsProvider = Provider<List<Tree>>((ref) {
  final run = ref.watch(activeRunProvider);
  if (run == null) return const [];
  return ref.watch(datasetPointsProvider(run.id)).valueOrNull ?? const [];
});

/// Clusters of the active run.
final clusterPointsProvider = Provider<List<Tree>>((ref) {
  final set = ref.watch(activeClusterSetProvider);
  if (set == null) return const [];
  return ref.watch(datasetPointsProvider(set.id)).valueOrNull ?? const [];
});

/// What the map draws and navigates: the run's points or its clusters.
final visiblePointsProvider = Provider<List<Tree>>((ref) {
  return ref.watch(clusterViewProvider)
      ? ref.watch(clusterPointsProvider)
      : ref.watch(runPointsProvider);
});

/// Reload what changed after a point or cluster was marked (not) visited.
void refreshAfterVisitedChange(WidgetRef ref, Tree tree) {
  ref.invalidate(datasetPointsProvider(tree.datasetId));
  ref.invalidate(treeByIdProvider(tree.id));
  ref.invalidate(datasetStatsProvider);
}

/// Reload after datasets were imported, created, deleted or cleared.
void refreshDatasets(WidgetRef ref, {Iterable<String> changedDatasetIds = const []}) {
  ref.invalidate(datasetsProvider);
  ref.invalidate(datasetStatsProvider);
  for (final id in changedDatasetIds) {
    ref.invalidate(datasetPointsProvider(id));
  }
}
