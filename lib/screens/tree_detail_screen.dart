import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/tree.dart';
import '../providers/location_provider.dart';
import '../providers/park_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../providers/trees_provider.dart';
import '../utils/distance_calculator.dart';
import '../utils/bearing_calculator.dart';

class TreeDetailScreen extends ConsumerWidget {
  const TreeDetailScreen({super.key, required this.treeId});

  final String treeId;

  Future<void> _toggleVisited(
    BuildContext context,
    WidgetRef ref,
    Tree tree,
  ) async {
    final next = !tree.visited;
    await ref.read(treeRepositoryProvider).setTreeVisited(tree.id, next);
    ref.invalidate(treeByIdProvider(tree.id));
    ref.invalidate(enabledTreesProvider);
    ref.invalidate(parkRouteProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Marked visited' : 'Marked not visited'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(treeByIdProvider(treeId));
    final locationAsync = ref.watch(locationStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Point details'),
      ),
      body: treeAsync.when(
        data: (tree) {
          if (tree == null) {
            return const Center(child: Text('Point not found'));
          }
          final userLoc = locationAsync.valueOrNull;
          final dist = userLoc != null
              ? calculateDistance(
                  userLoc.latitude,
                  userLoc.longitude,
                  tree.latitude,
                  tree.longitude,
                )
              : null;
          final bearing = userLoc != null
              ? calculateBearing(
                  userLoc.latitude,
                  userLoc.longitude,
                  tree.latitude,
                  tree.longitude,
                )
              : null;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TreeHeader(tree: tree, dist: dist, bearing: bearing),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _toggleVisited(context, ref, tree),
                    icon: Icon(
                      tree.visited ? Icons.check_circle : Icons.radio_button_unchecked,
                    ),
                    label: Text(tree.visited ? 'Mark not visited' : 'Mark visited'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _TreeHeader extends StatelessWidget {
  const _TreeHeader({required this.tree, this.dist, this.bearing});

  final Tree tree;
  final double? dist;
  final double? bearing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ClassificationChip(classification: tree.treeClassification),
            if (tree.visited)
              const Chip(
                avatar: Icon(Icons.check, size: 16),
                label: Text('Visited'),
                backgroundColor: Colors.greenAccent,
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (tree.predictionScore != null)
          Text(
            '${tree.predictionScore!.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        if (tree.classification != null)
          Text(tree.classification!, style: Theme.of(context).textTheme.titleMedium),
        if (tree.description != null) ...[
          const SizedBox(height: 8),
          Text(tree.description!),
        ],
        const SizedBox(height: 8),
        Text(tree.filename, style: Theme.of(context).textTheme.bodySmall),
        if (dist != null && bearing != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        formatDistance(dist!),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text('Distance'),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        formatBearing(bearing!),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text('Bearing'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClassificationChip extends StatelessWidget {
  const _ClassificationChip({required this.classification});

  final TreeClassification classification;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(classification);
    return Chip(
      backgroundColor: color.withOpacity(0.2),
      label: Text(label),
      avatar: CircleAvatar(backgroundColor: color, radius: 10),
    );
  }

  (String, Color) _labelAndColor(TreeClassification c) {
    switch (c) {
      case TreeClassification.environment:
        return ('Environment', AppTheme.environmentColor);
      case TreeClassification.sick:
        return ('Sick', AppTheme.sickColor);
      case TreeClassification.dead:
        return ('Dead', AppTheme.deadColor);
    }
  }
}
