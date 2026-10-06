import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree.dart';
import 'tree_repository_provider.dart';

/// Points of one dataset (a run or a cluster set). Kept in memory once
/// loaded, so switching between point and cluster view is instant.
final datasetPointsProvider =
    FutureProvider.family<List<Tree>, String>((ref, datasetId) async {
  final repo = ref.watch(treeRepositoryProvider);
  return repo.getTreesByDataset(datasetId);
});

final treeByIdProvider = FutureProvider.family<Tree?, String>((ref, id) async {
  final repo = ref.watch(treeRepositoryProvider);
  return repo.getTreeById(id);
});
