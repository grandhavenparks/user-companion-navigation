import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import '../services/database_service.dart';
import 'dataset_repository_provider.dart';

/// Runs and cluster sets, newest first.
final datasetsProvider = FutureProvider<List<Dataset>>((ref) async {
  final repo = ref.watch(datasetRepositoryProvider);
  return repo.getAllDatasets();
});

/// Points / visited points per dataset id (for the Home list).
final datasetStatsProvider =
    FutureProvider<Map<String, DatasetStats>>((ref) async {
  final repo = ref.watch(datasetRepositoryProvider);
  return repo.getDatasetStats();
});
