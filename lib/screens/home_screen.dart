import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../providers/basemap_provider.dart';
import '../providers/dataset_provider.dart';
import '../providers/dataset_repository_provider.dart';
import '../providers/park_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../providers/trees_provider.dart';
import '../services/csv_points_parser_service.dart';
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
          ref.invalidate(datasetsProvider);
          ref.invalidate(enabledTreesProvider);
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
                    onPressed: () => _exportVisited(context, ref),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Export visited'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _clearVisitedPrompt(context, ref),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear visited'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Datasets', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...datasetsAsync.when<List<Widget>>(
              loading: () => [const Center(child: CircularProgressIndicator())],
              error: (e, _) => [Text('Could not load datasets: $e')],
              data: (datasets) => datasets.isEmpty
                  ? [const _EmptyDatasets()]
                  : [
                      for (final dataset in datasets)
                        _DatasetCard(
                          dataset: dataset,
                          onToggle: (enabled) =>
                              _setEnabled(ref, dataset.id, enabled),
                          onDelete: () => _deleteDataset(context, ref, dataset),
                        ),
                    ],
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

  Future<void> _setEnabled(WidgetRef ref, String id, bool enabled) async {
    await ref.read(datasetRepositoryProvider).setDatasetEnabled(id, enabled);
    ref.invalidate(datasetsProvider);
    ref.invalidate(enabledTreesProvider);
  }

  Future<void> _deleteDataset(
    BuildContext context,
    WidgetRef ref,
    Dataset dataset,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dataset?'),
        content: Text(
          'This removes "${dataset.name}" and its ${dataset.treeCount} points, '
          'including their visited marks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(datasetRepositoryProvider).deleteDataset(dataset.id);
      ref.invalidate(datasetsProvider);
      ref.invalidate(enabledTreesProvider);
    }
  }

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
    ref.invalidate(datasetsProvider);
    ref.invalidate(enabledTreesProvider);

    final lines = [...result.report!.summaryLines()];
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

  Future<void> _exportVisited(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(treeRepositoryProvider);
    final visited = await repo.getVisitedTrees();
    if (visited.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No visited points yet')));
      return;
    }
    final datasets = await ref.read(datasetRepositoryProvider).getAllDatasets();
    try {
      await shareVisitedPointsCsv(
        visited,
        datasetNames: {for (final d in datasets) d.id: d.name},
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      return;
    }
    if (!context.mounted) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear visited marks?'),
        content: Text(
          'Unmark all ${visited.length} visited point(s) now that they are exported?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear == true) {
      await repo.clearAllVisitedState();
      ref.invalidate(enabledTreesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Visited marks cleared')));
    }
  }

  Future<void> _clearVisitedPrompt(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(treeRepositoryProvider);
    final visited = await repo.getVisitedTrees();
    if (!context.mounted) return;
    if (visited.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No visited points to clear')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all visited marks?'),
        content: Text(
          'This unmarks ${visited.length} point(s). It cannot be undone; '
          'export first if you need a record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.clearAllVisitedState();
      ref.invalidate(enabledTreesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Visited marks cleared')));
    }
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

class _EmptyDatasets extends StatelessWidget {
  const _EmptyDatasets();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.folder_open, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No datasets yet', style: Theme.of(context).textTheme.titleMedium),
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

class _DatasetCard extends StatelessWidget {
  const _DatasetCard({
    required this.dataset,
    required this.onToggle,
    required this.onDelete,
  });

  final Dataset dataset;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final imported = dataset.importedAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(dataset.name),
        subtitle: Text(
          '${dataset.treeCount} points'
          '${imported != null ? ' · ${_formatDate(imported)}' : ''}'
          '${dataset.enabled ? '' : ' · hidden'}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: dataset.enabled, onChanged: onToggle),
            IconButton(
              tooltip: 'Delete dataset',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
