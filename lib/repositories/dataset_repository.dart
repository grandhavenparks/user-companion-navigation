import '../models/dataset.dart';
import '../models/tree.dart';
import '../services/database_service.dart';

class DatasetRepository {
  DatasetRepository(this._db);

  final DatabaseService _db;

  /// Runs and cluster sets, newest first.
  Future<List<Dataset>> getAllDatasets() => _db.getAllDatasets();

  /// Saves an imported run and its points atomically.
  Future<void> importDataset(Dataset dataset, List<Tree> trees) =>
      _db.insertDatasetWithTrees(dataset, trees);

  /// Replaces the cluster set of [runId] (fresh clusters, all unvisited).
  Future<void> replaceClusterSet(
    String runId,
    Dataset clusterSet,
    List<Tree> clusters,
  ) =>
      _db.replaceClusterSet(runId, clusterSet, clusters);

  /// Deletes a run (with its clusters) or a cluster set.
  Future<void> deleteDataset(String id) => _db.deleteDataset(id);

  Future<Map<String, DatasetStats>> getDatasetStats() => _db.getDatasetStats();
}
