import '../models/visit_record.dart';
import '../services/database_service.dart';

class VisitRepository {
  VisitRepository(this._db);

  final DatabaseService _db;

  Future<List<VisitRecord>> getVisitsByTreeId(String treeId) =>
      _db.getVisitRecordsByTreeId(treeId);

  Future<void> saveVisit(VisitRecord record) => _db.insertVisitRecord(record);
}
