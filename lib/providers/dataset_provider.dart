import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dataset.dart';
import 'dataset_repository_provider.dart';

final datasetsProvider = FutureProvider<List<Dataset>>((ref) async {
  final repo = ref.watch(datasetRepositoryProvider);
  return repo.getAllDatasets();
});
