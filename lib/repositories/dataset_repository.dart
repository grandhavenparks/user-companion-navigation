import '../models/dataset.dart';
import '../models/tree.dart';
import '../services/database_service.dart';

class DatasetRepository {
  DatasetRepository(this._db);

  final DatabaseService _db;

  Future<List<Dataset>> getAllDatasets() => _db.getAllDatasets();

  /// Saves the dataset and its points atomically.
  Future<void> importDataset(Dataset dataset, List<Tree> trees) =>
      _db.insertDatasetWithTrees(dataset, trees);

  Future<void> setDatasetEnabled(String id, bool enabled) =>
      _db.updateDatasetEnabled(id, enabled);

  Future<void> deleteDataset(String id) => _db.deleteDataset(id);
}
