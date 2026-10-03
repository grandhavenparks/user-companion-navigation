import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/visit_record.dart';
import 'visit_repository_provider.dart';

final visitsForTreeProvider =
    FutureProvider.family<List<VisitRecord>, String>((ref, treeId) async {
  final repo = ref.watch(visitRepositoryProvider);
  return repo.getVisitsByTreeId(treeId);
});
