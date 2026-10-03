import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datasetsAsync = ref.watch(datasetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: datasetsAsync.when(
        data: (datasets) => _buildBody(context, ref, datasets),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importCSV(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('Import CSV'),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Dataset> datasets,
  ) {
    if (datasets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No datasets yet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap "Import CSV" to load points from your points folder.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ParkMapScreen(),
                  ),
                ),
                icon: const Icon(Icons.map),
                label: const Text('Open Park Map'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(datasetsProvider.future),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: datasets.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ParkMapScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.map),
                    label: const Text('Open Park Map'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _exportVisitedCsv(context, ref),
                    icon: const Icon(Icons.download),
                    label: const Text('Export visited points (CSV)'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _clearVisitedPrompt(context, ref),
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear visited marks'),
                  ),
                ],
              ),
            );
          }
          final dataset = datasets[index - 1];
          return _DatasetCard(
            dataset: dataset,
            onToggle: (enabled) => _setEnabled(ref, dataset.id, enabled),
            onDelete: () => _deleteDataset(context, ref, dataset.id),
          );
        },
      ),
    );
  }

  Future<void> _setEnabled(WidgetRef ref, String id, bool enabled) async {
    await ref.read(datasetRepositoryProvider).setDatasetEnabled(id, enabled);
    ref.invalidate(datasetsProvider);
  }

  Future<void> _deleteDataset(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dataset?'),
        content: const Text(
          'This will remove the dataset and all its trees from the device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(datasetRepositoryProvider).deleteDataset(id);
      ref.invalidate(datasetsProvider);
      ref.invalidate(enabledTreesProvider);
    }
  }

  Future<void> _importCSV(BuildContext context, WidgetRef ref) async {
    final result = await pickAndReadCSV();
    if (!result.success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Import failed')),
        );
      }
      return;
    }

    final parseResult = parsePointsCsv(
      result.content!,
      sourceName: result.fileName ?? 'imported_points.csv',
    );
    if (!parseResult.success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parseResult.error ?? 'Parse failed')),
        );
      }
      return;
    }

    final dataset = parseResult.dataset!;
    final repo = ref.read(datasetRepositoryProvider);
    final treeRepo = ref.read(treeRepositoryProvider);
    await repo.saveDataset(dataset);
    await treeRepo.saveTrees(parseResult.trees!);

    ref.invalidate(datasetsProvider);
    ref.invalidate(enabledTreesProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported "${dataset.name}" with ${dataset.treeCount} points',
          ),
        ),
      );
    }
  }

  Future<void> _exportVisitedCsv(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(treeRepositoryProvider);
    final visited = await repo.getVisitedTrees();
    if (!context.mounted) return;
    if (visited.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No visited points yet')),
      );
      return;
    }
    await shareVisitedPointsCsv(visited);
    if (!context.mounted) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear visited marks?'),
        content: const Text(
          'Remove visited flags for all points in the app? Export is already shared.',
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
    if (shouldClear == true) {
      await repo.clearAllVisitedState();
      ref.invalidate(enabledTreesProvider);
      ref.invalidate(parkRouteProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visited marks cleared')),
        );
      }
    }
  }

  Future<void> _clearVisitedPrompt(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(treeRepositoryProvider);
    final visited = await repo.getVisitedTrees();
    if (!context.mounted) return;
    if (visited.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No visited points to clear')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all visited marks?'),
        content: Text(
          'This will unmark ${visited.length} point(s). This cannot be undone.',
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
      ref.invalidate(parkRouteProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visited marks cleared')),
        );
      }
    }
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(dataset.name),
        subtitle: Text(
          '${dataset.treeCount} trees'
          '${dataset.importedAt != null ? " · ${_formatDate(dataset.importedAt!)}" : ""}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: dataset.enabled,
              onChanged: onToggle,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
