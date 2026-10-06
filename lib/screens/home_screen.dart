import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../models/tree.dart';
import '../providers/basemap_provider.dart';
import '../providers/dataset_provider.dart';
import '../providers/dataset_repository_provider.dart';
import '../providers/park_provider.dart';
import '../providers/run_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../services/csv_points_parser_service.dart';
import '../services/database_service.dart';
import '../services/file_import_service.dart';
import '../services/visited_points_export_service.dart';
import 'park_map_screen.dart';
import 'settings_screen.dart';

/// Runs in a background isolate so large CSV files do not freeze the UI.
CsvPointsParseResult _parsePicked(PickedFile file) =>
    parsePointsCsvBytes(file.bytes, sourceName: file.name);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datasetsAsync = ref.watch(datasetsProvider);
    final stats = ref.watch(datasetStatsProvider).valueOrNull ?? const {};
    final activeRun = ref.watch(activeRunProvider);
    // Watching also prepares the offline map in the background at start-up.
    // Only a problem is shown here; a working map needs no message.
    final basemapAsync = ref.watch(basemapProvider);
    final basemapProblem = basemapAsync.hasError
        ? 'Offline map error: ${basemapAsync.error}'
        : (basemapAsync.valueOrNull?.isReady ?? true)
            ? null
            : basemapAsync.valueOrNull?.message ?? 'Offline map unavailable';

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          refreshDatasets(ref);
          await ref.read(datasetsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ParkMapScreen()),
              ),
              icon: const Icon(Icons.map),
              label: const Text('Open park map'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            if (basemapProblem != null) ...[
              const SizedBox(height: 8),
              _BasemapWarning(message: basemapProblem),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: activeRun == null
                        ? null
                        : () => _exportVisited(context, ref, activeRun),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export visited'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: activeRun == null
                        ? null
                        : () => _clearVisited(context, ref, activeRun),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear visited'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Runs', style: Theme.of(context).textTheme.titleMedium),
            Text(
              'One run (CSV) is used on the map at a time. Tap a run to use it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ...datasetsAsync.when<List<Widget>>(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (e, _) => [Text('Could not load runs: $e')],
              data: (datasets) {
                final runs = [for (final d in datasets) if (d.isRun) d];
                if (runs.isEmpty) return [const _EmptyRuns()];
                return [
                  for (final run in runs)
                    _RunCard(
                      run: run,
                      clusterSet: clusterSetOf(datasets, run.id),
                      stats: stats,
                      active: run.id == activeRun?.id,
                      onSelect: () => ref
                          .read(settingsProvider.notifier)
                          .setActiveRunId(run.id),
                      onDeleteRun: () => _deleteRun(context, ref, run),
                      onDeleteClusters: (set) =>
                          _deleteClusterSet(context, ref, run, set),
                    ),
                ];
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importCsv(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('Import CSV'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Runs
  // ---------------------------------------------------------------------------

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteRun(BuildContext context, WidgetRef ref, Dataset run) async {
    final ok = await _confirm(
      context,
      title: 'Delete run?',
      message: 'This removes "${run.name}" with its ${run.treeCount} points, '
          'its clusters and all their visited marks.',
      action: 'Delete',
    );
    if (!ok) return;
    await ref.read(datasetRepositoryProvider).deleteDataset(run.id);
    if (ref.read(settingsProvider).activeRunId == run.id) {
      await ref.read(settingsProvider.notifier).setActiveRunId(null);
    }
    refreshDatasets(ref);
  }

  Future<void> _deleteClusterSet(
    BuildContext context,
    WidgetRef ref,
    Dataset run,
    Dataset clusterSet,
  ) async {
    final ok = await _confirm(
      context,
      title: 'Delete clusters?',
      message: 'This removes the ${clusterSet.treeCount} clusters of '
          '"${run.name}" and their visited marks. The run\'s points stay.',
      action: 'Delete',
    );
    if (!ok) return;
    await ref.read(datasetRepositoryProvider).deleteDataset(clusterSet.id);
    refreshDatasets(ref);
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final PickedFile? picked;
    try {
      picked = await pickPointsFile();
    } on FileImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not open the file: $e')));
      return;
    }
    if (picked == null) return;

    final result = await compute(_parsePicked, picked);
    if (!result.success) {
      if (context.mounted) {
        await _showReport(context, 'Import failed', [result.error ?? 'Unknown error']);
      }
      return;
    }

    final dataset = result.dataset!;
    final trees = result.trees!;
    try {
      await ref.read(datasetRepositoryProvider).importDataset(dataset, trees);
    } catch (e) {
      if (context.mounted) {
        await _showReport(context, 'Import failed', ['Saving failed: $e']);
      }
      return;
    }
    // A newly imported run becomes the one used on the map.
    await ref.read(settingsProvider.notifier).setActiveRunId(dataset.id);
    refreshDatasets(ref);

    final lines = [
      ...result.report!.summaryLines(),
      'This run is now used on the map.',
    ];
    try {
      final parks = (await ref.read(parksProvider.future)).parks;
      if (parks.isEmpty) {
        lines.add('No parks are bundled, so nothing can be navigated yet.');
      } else {
        final outside = trees
            .where((t) => findParkMembership(parks, t.latitude, t.longitude) == null)
            .length;
        lines.add(outside == 0
            ? 'All points are inside a bundled park.'
            : '$outside of ${trees.length} points are outside every bundled '
                'park. They are shown on the map in grey but are not '
                'included in navigation.');
      }
    } catch (_) {
      // Park check is informational only.
    }
    if (context.mounted) {
      await _showReport(context, 'Imported "${dataset.name}"', lines);
    }
  }

  Future<void> _showReport(BuildContext context, String title, List<String> lines) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(line),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Visited
  // ---------------------------------------------------------------------------

  /// Exports the active run's visited points and visited clusters in one
  /// file (`type` column = point / cluster).
  Future<void> _exportVisited(BuildContext context, WidgetRef ref, Dataset run) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(treeRepositoryProvider);
    final clusterSet = ref.read(activeClusterSetProvider);
    final points = await repo.getVisitedTreesByDataset(run.id);
    final List<Tree> clusters = clusterSet == null
        ? const []
        : await repo.getVisitedTreesByDataset(clusterSet.id);
    if (points.isEmpty && clusters.isEmpty) {
      messenger.showSnackBar(
          SnackBar(content: Text('Nothing visited yet in "${run.name}"')));
      return;
    }
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export visited'),
        content: Text('${points.length} visited point(s) and ${clusters.length} '
            'visited cluster(s) of "${run.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: const Text('Share'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save to device'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'save') {
        final saved = await saveCsvToDevice(
          fileName: visitedFileName(run.name),
          csv: buildVisitedCsv(runName: run.name, points: points, clusters: clusters),
          dialogTitle: 'Save visited CSV',
        );
        messenger.showSnackBar(
            SnackBar(content: Text(saved ? 'Saved to device' : 'Save cancelled')));
        if (!saved) return;
      } else {
        await shareVisitedCsv(runName: run.name, points: points, clusters: clusters);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      return;
    }
    if (!context.mounted) return;
    final clear = await _confirm(
      context,
      title: 'Clear visited marks?',
      message: 'Unmark the ${points.length} visited point(s) and '
          '${clusters.length} visited cluster(s) of "${run.name}" now that '
          'they are exported?',
      action: 'Clear',
    );
    if (!clear) return;
    await repo.clearVisitedForDataset(run.id);
    if (clusterSet != null) await repo.clearVisitedForDataset(clusterSet.id);
    refreshDatasets(
      ref,
      changedDatasetIds: [run.id, if (clusterSet != null) clusterSet.id],
    );
    messenger.showSnackBar(const SnackBar(content: Text('Visited marks cleared')));
  }

  /// Clears visited marks of the view last used on the map: the run's points
  /// in point view, its clusters in cluster view.
  Future<void> _clearVisited(BuildContext context, WidgetRef ref, Dataset run) async {
    final messenger = ScaffoldMessenger.of(context);
    final clusterView = ref.read(clusterViewProvider);
    final clusterSet = ref.read(activeClusterSetProvider);
    final target = clusterView ? clusterSet : run;
    if (target == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('This run has no clusters yet')));
      return;
    }
    final visited = ref.read(datasetStatsProvider).valueOrNull?[target.id]?.visited ?? 0;
    if (visited == 0) {
      messenger.showSnackBar(SnackBar(
        content: Text(clusterView
            ? 'No visited clusters to clear'
            : 'No visited points to clear'),
      ));
      return;
    }
    final noun = clusterView ? 'cluster(s)' : 'point(s)';
    final ok = await _confirm(
      context,
      title: clusterView ? 'Clear visited clusters?' : 'Clear visited points?',
      message: 'This unmarks $visited visited $noun of "${run.name}" '
          '(${clusterView ? 'cluster' : 'point'} view is selected on the map). '
          'It cannot be undone; export first if you need a record.',
      action: 'Clear',
    );
    if (!ok) return;
    await ref.read(treeRepositoryProvider).clearVisitedForDataset(target.id);
    refreshDatasets(ref, changedDatasetIds: [target.id]);
    messenger.showSnackBar(const SnackBar(content: Text('Visited marks cleared')));
  }
}

class _BasemapWarning extends StatelessWidget {
  const _BasemapWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(Icons.map_outlined, color: scheme.error),
      title: Text(message),
    );
  }
}

class _EmptyRuns extends StatelessWidget {
  const _EmptyRuns();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.folder_open, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No runs yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Tap "Import CSV" and pick a results file with latitude and '
            'longitude columns.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.run,
    required this.clusterSet,
    required this.stats,
    required this.active,
    required this.onSelect,
    required this.onDeleteRun,
    required this.onDeleteClusters,
  });

  final Dataset run;
  final Dataset? clusterSet;
  final Map<String, DatasetStats> stats;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onDeleteRun;
  final ValueChanged<Dataset> onDeleteClusters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imported = run.importedAt;
    final runStats = stats[run.id];
    final set = clusterSet;
    final setStats = set == null ? null : stats[set.id];

    final pointsLine = '${runStats?.total ?? run.treeCount} points'
        '${runStats == null ? '' : ' · ${runStats.visited} visited'}'
        '${imported != null ? ' · ${_formatDate(imported)}' : ''}';
    final clustersLine = set == null
        ? 'No clusters'
        : 'Clusters: ${setStats?.total ?? set.treeCount}'
            '${setStats == null ? '' : ' · ${setStats.visited} visited'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: active
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: ListTile(
        onTap: onSelect,
        leading: Icon(
          active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: active ? theme.colorScheme.primary : null,
        ),
        title: Text(run.name),
        subtitle: Text('$pointsLine\n$clustersLine'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          tooltip: 'Run options',
          onSelected: (value) {
            if (value == 'delete_clusters' && set != null) onDeleteClusters(set);
            if (value == 'delete_run') onDeleteRun();
          },
          itemBuilder: (_) => [
            if (set != null)
              const PopupMenuItem(
                value: 'delete_clusters',
                child: Text('Delete clusters'),
              ),
            const PopupMenuItem(
              value: 'delete_run',
              child: Text('Delete run'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
