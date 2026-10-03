import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/tree_repository.dart';
import 'database_provider.dart';

final treeRepositoryProvider = Provider<TreeRepository>((ref) {
  return TreeRepository(ref.watch(databaseServiceProvider));
});
