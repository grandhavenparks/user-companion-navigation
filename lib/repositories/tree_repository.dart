import '../models/tree.dart';
import '../services/database_service.dart';

class TreeRepository {
  TreeRepository(this._db);

  final DatabaseService _db;

  Future<List<Tree>> getTreesByDatasetId(String datasetId) =>
      _db.getTreesByDatasetId(datasetId);

  Future<List<Tree>> getTreesFromEnabledDatasets() =>
      _db.getTreesFromEnabledDatasets();

  Future<Tree?> getTreeById(String id) => _db.getTreeById(id);

  Future<void> saveTrees(List<Tree> trees) => _db.insertTrees(trees);

  Future<void> setTreeVisited(String treeId, bool visited) =>
      _db.updateTreeVisited(treeId, visited);
  
  Future<void> setTreeVisitedWithNotes(String treeId, String notes) =>
      _db.updateTreeWithNotes(treeId, notes);

  Future<List<Tree>> getVisitedTrees() => _db.getVisitedTrees();

  Future<void> clearAllVisitedState() => _db.clearAllVisitedState();
}
