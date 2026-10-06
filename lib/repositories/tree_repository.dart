import '../models/tree.dart';
import '../services/database_service.dart';

class TreeRepository {
  TreeRepository(this._db);

  final DatabaseService _db;

  Future<List<Tree>> getTreesByDataset(String datasetId) =>
      _db.getTreesByDataset(datasetId);

  Future<Tree?> getTreeById(String id) => _db.getTreeById(id);

  Future<void> setTreeVisited(String treeId, bool visited) =>
      _db.updateTreeVisited(treeId, visited);

  Future<List<Tree>> getVisitedTreesByDataset(String datasetId) =>
      _db.getVisitedTreesByDataset(datasetId);

  Future<void> clearVisitedForDataset(String datasetId) =>
      _db.clearVisitedForDataset(datasetId);
}
