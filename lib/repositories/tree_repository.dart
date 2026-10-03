import '../models/tree.dart';
import '../services/database_service.dart';

class TreeRepository {
  TreeRepository(this._db);

  final DatabaseService _db;

  Future<List<Tree>> getTreesFromEnabledDatasets() =>
      _db.getTreesFromEnabledDatasets();

  Future<Tree?> getTreeById(String id) => _db.getTreeById(id);

  Future<void> setTreeVisited(String treeId, bool visited) =>
      _db.updateTreeVisited(treeId, visited);

  Future<List<Tree>> getVisitedTrees() => _db.getVisitedTrees();

  Future<void> clearAllVisitedState() => _db.clearAllVisitedState();
}
