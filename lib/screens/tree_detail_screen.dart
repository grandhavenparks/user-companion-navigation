import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/dataset.dart';
import '../models/park.dart';
import '../models/tree.dart';
import '../providers/dataset_provider.dart';
import '../providers/location_provider.dart';
import '../providers/park_provider.dart';
import '../providers/run_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../providers/trees_provider.dart';
import '../utils/bearing_calculator.dart';
import '../utils/distance_calculator.dart';

/// Details of a point or a cluster, with Mark visited / not visited.
class TreeDetailScreen extends ConsumerWidget {
  const TreeDetailScreen({super.key, required this.treeId});

  final String treeId;

  Future<void> _setVisited(
    BuildContext context,
    WidgetRef ref,
    Tree tree,
    bool visited,
  ) async {
    await ref.read(treeRepositoryProvider).setTreeVisited(tree.id, visited);
    refreshAfterVisitedChange(ref, tree);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(visited ? 'Marked visited' : 'Marked not visited')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(treeByIdProvider(treeId));
    final location = ref.watch(locationControllerProvider).location;
    final parks = ref.watch(parksProvider).valueOrNull?.parks ?? const <Park>[];
    final datasets = ref.watch(datasetsProvider).valueOrNull ?? const <Dataset>[];
    final useFeet = ref.watch(settingsProvider.select((s) => s.useFeet));

    return Scaffold(
      appBar: AppBar(
        title: Text(treeAsync.valueOrNull?.isCluster ?? false
            ? 'Cluster details'
            : 'Point details'),
      ),
      body: treeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tree) {
          if (tree == null) {
            return const Center(child: Text('Not found'));
          }
          final theme = Theme.of(context);
          final membership = membershipOf(parks, tree);
          final runName = _runName(datasets, tree.datasetId);
          final distance = location == null
              ? null
              : calculateDistance(location.latitude, location.longitude,
                  tree.latitude, tree.longitude);
          final bearing = location == null
              ? null
              : calculateBearing(location.latitude, location.longitude,
                  tree.latitude, tree.longitude);
          final coordinates =
              '${tree.latitude.toStringAsFixed(7)}, ${tree.longitude.toStringAsFixed(7)}';
          final count = tree.memberCount;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(tree.filename,
                        style: theme.textTheme.headlineSmall),
                  ),
                  Chip(
                    avatar: Icon(
                      tree.visited ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 18,
                      color: tree.visited ? AppTheme.visitedColor : null,
                    ),
                    label: Text(tree.visited ? 'Visited' : 'Not visited'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (tree.isCluster) ...[
                Text(
                  count != null && count > 0
                      ? '$count ${count == 1 ? 'tree' : 'trees'} in this cluster'
                      : 'Number of trees unknown (imported cluster file)',
                  style: theme.textTheme.titleMedium,
                ),
                if (tree.classification != null)
                  Text('Most common classification: ${tree.classification}'),
              ] else ...[
                if (tree.classification != null)
                  Text(tree.classification!, style: theme.textTheme.titleMedium),
                if (tree.confidenceLabel != null)
                  Text('Confidence ${tree.confidenceLabel}'),
              ],
              if (tree.description != null) ...[
                const SizedBox(height: 8),
                Text(tree.description!),
              ],
              const SizedBox(height: 16),
              if (distance != null && bearing != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Metric(
                          value: formatDistance(distance, useFeet: useFeet),
                          label: 'Distance',
                        ),
                        _Metric(value: formatBearing(bearing), label: 'Bearing'),
                      ],
                    ),
                  ),
                )
              else
                const Text('Waiting for GPS to show distance and bearing...'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text(coordinates),
                subtitle: Text(tree.isCluster
                    ? 'Average position of its trees (WGS84)'
                    : 'Latitude, longitude (WGS84)'),
                trailing: IconButton(
                  tooltip: 'Copy coordinates',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: coordinates));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coordinates copied')),
                      );
                    }
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  membership == null ? Icons.do_not_disturb_on_outlined : Icons.park,
                  color: membership == null ? AppTheme.outsideColor : AppTheme.visitedColor,
                ),
                title: Text(membership == null
                    ? 'Outside all parks'
                    : [
                        membership.park.name,
                        membership.park.areaLabel(membership.areaIndex),
                      ].where((s) => s.isNotEmpty).join(', ')),
                subtitle: Text(membership == null
                    ? 'Shown on the map, not part of navigation'
                    : 'Included in navigation'),
              ),
              if (runName != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(runName),
                  subtitle: Text(tree.isCluster ? 'Clusters of run' : 'Run'),
                ),
              if (tree.visited && tree.visitedAt != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(tree.visitedAt!.toLocal().toString().split('.').first),
                  subtitle: const Text('Visited at'),
                ),
              if (tree.isCluster && tree.members.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: const Icon(Icons.list),
                  title: Text('Trees in this cluster (${tree.members.length})'),
                  children: [
                    for (final member in tree.members)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 16),
                        title: Text(member),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _setVisited(context, ref, tree, !tree.visited),
                icon: Icon(tree.visited ? Icons.undo : Icons.check_circle),
                label: Text(tree.visited ? 'Mark not visited' : 'Mark visited'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Run name for a point, or the parent run's name for a cluster.
  String? _runName(List<Dataset> datasets, String datasetId) {
    Dataset? find(String? id) {
      for (final d in datasets) {
        if (d.id == id) return d;
      }
      return null;
    }

    final dataset = find(datasetId);
    if (dataset == null) return null;
    if (dataset.isClusterSet) return find(dataset.parentId)?.name ?? dataset.name;
    return dataset.name;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label),
      ],
    );
  }
}
