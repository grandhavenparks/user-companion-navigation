import '../models/dataset.dart';
import '../services/database_service.dart';

class DatasetRepository {
  DatasetRepository(this._db);

  final DatabaseService _db;

  Future<List<Dataset>> getAllDatasets() => _db.getAllDatasets();

  Future<Dataset?> getDatasetById(String id) => _db.getDatasetById(id);

  Future<void> saveDataset(Dataset dataset) => _db.insertDataset(dataset);

  Future<void> setDatasetEnabled(String id, bool enabled) =>
      _db.updateDatasetEnabled(id, enabled);

  Future<void> deleteDataset(String id) => _db.deleteDataset(id);
}
