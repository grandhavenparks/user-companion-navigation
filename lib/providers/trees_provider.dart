import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree.dart';
import 'tree_repository_provider.dart';

final enabledTreesProvider = FutureProvider<List<Tree>>((ref) async {
  final repo = ref.watch(treeRepositoryProvider);
  return repo.getTreesFromEnabledDatasets();
});

final treeByIdProvider = FutureProvider.family<Tree?, String>((ref, id) async {
  final repo = ref.watch(treeRepositoryProvider);
  return repo.getTreeById(id);
});
