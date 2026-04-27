import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/dataset_repository.dart';
import 'database_provider.dart';

final datasetRepositoryProvider = Provider<DatasetRepository>((ref) {
  return DatasetRepository(ref.watch(databaseServiceProvider));
});
