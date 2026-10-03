import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/visit_repository.dart';
import 'database_provider.dart';

final visitRepositoryProvider = Provider<VisitRepository>((ref) {
  return VisitRepository(ref.watch(databaseServiceProvider));
});
