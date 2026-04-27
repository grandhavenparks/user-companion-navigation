import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../models/tree.dart';
import '../models/visit_record.dart';

/// SQLite database for trees, datasets, and visits.
class DatabaseService {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConfig.databaseName);
    return openDatabase(
      path,
      version: AppConfig.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add visit_notes column to trees table
      await db.execute('ALTER TABLE trees ADD COLUMN visit_notes TEXT');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE datasets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        tree_count INTEGER NOT NULL,
        imported_at TEXT,
        disease_type TEXT,
        enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE trees (
        id TEXT PRIMARY KEY,
        dataset_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        image_s3_key TEXT,
        prediction_score REAL,
        predicted_class TEXT,
        classification TEXT,
        description TEXT,
        visited INTEGER NOT NULL DEFAULT 0,
        visited_at TEXT,
        visit_notes TEXT,
        FOREIGN KEY (dataset_id) REFERENCES datasets (id)
      )
    ''');
    await db.execute('''
      CREATE TABLE visit_records (
        id TEXT PRIMARY KEY,
        tree_id TEXT NOT NULL,
        visited_at TEXT NOT NULL,
        notes TEXT,
        photo_paths TEXT,
        FOREIGN KEY (tree_id) REFERENCES trees (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_trees_dataset ON trees(dataset_id)',
    );
    await db.execute(
      'CREATE INDEX idx_trees_visited ON trees(visited)',
    );
    await db.execute(
      'CREATE INDEX idx_visit_records_tree ON visit_records(tree_id)',
    );
  }

  // Datasets
  Future<void> insertDataset(Dataset dataset) async {
    final db = await database;
    await db.insert('datasets', dataset.toMap());
  }

  Future<List<Dataset>> getAllDatasets() async {
    final db = await database;
    final maps = await db.query('datasets', orderBy: 'imported_at DESC');
    return maps.map((m) => Dataset.fromMap(m)).toList();
  }

  Future<Dataset?> getDatasetById(String id) async {
    final db = await database;
    final maps = await db.query('datasets', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Dataset.fromMap(maps.first);
  }

  Future<void> updateDatasetEnabled(String id, bool enabled) async {
    final db = await database;
    await db.update(
      'datasets',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDataset(String id) async {
    final db = await database;
    await db.delete('trees', where: 'dataset_id = ?', whereArgs: [id]);
    await db.delete('datasets', where: 'id = ?', whereArgs: [id]);
  }

  // Trees
  Future<void> insertTrees(List<Tree> trees) async {
    if (trees.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final t in trees) {
      batch.insert('trees', t.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Tree>> getTreesByDatasetId(String datasetId) async {
    final db = await database;
    final maps = await db.query(
      'trees',
      where: 'dataset_id = ?',
      whereArgs: [datasetId],
    );
    return maps.map((m) => Tree.fromMap(m)).toList();
  }

  Future<List<Tree>> getTreesFromEnabledDatasets() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM trees t
      INNER JOIN datasets d ON t.dataset_id = d.id
      WHERE d.enabled = 1
    ''');
    return maps.map((m) => Tree.fromMap(m)).toList();
  }

  Future<Tree?> getTreeById(String id) async {
    final db = await database;
    final maps = await db.query('trees', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Tree.fromMap(maps.first);
  }

  Future<void> updateTreeVisited(String treeId, bool visited) async {
    final db = await database;
    final values = <String, Object?>{
      'visited': visited ? 1 : 0,
      'visited_at': visited ? DateTime.now().toIso8601String() : null,
    };
    if (!visited) {
      values['visit_notes'] = null;
    }
    await db.update(
      'trees',
      values,
      where: 'id = ?',
      whereArgs: [treeId],
    );
  }

  /// All trees marked visited (any dataset).
  Future<List<Tree>> getVisitedTrees() async {
    final db = await database;
    final maps = await db.query(
      'trees',
      where: 'visited = ?',
      whereArgs: [1],
      orderBy: 'visited_at DESC',
    );
    return maps.map((m) => Tree.fromMap(m)).toList();
  }

  /// Reset visited flags and remove visit log rows (after export / user reset).
  Future<void> clearAllVisitedState() async {
    final db = await database;
    await db.delete('visit_records');
    await db.rawUpdate('''
      UPDATE trees SET visited = 0, visited_at = NULL, visit_notes = NULL
      WHERE visited = 1
    ''');
  }
  
  Future<void> updateTreeWithNotes(String treeId, String notes) async {
    final db = await database;
    await db.update(
      'trees',
      {
        'visited': 1,
        'visited_at': DateTime.now().toIso8601String(),
        'visit_notes': notes,
      },
      where: 'id = ?',
      whereArgs: [treeId],
    );
  }

  // Visit records
  Future<void> insertVisitRecord(VisitRecord record) async {
    final db = await database;
    await db.insert('visit_records', record.toMap());
  }

  Future<List<VisitRecord>> getVisitRecordsByTreeId(String treeId) async {
    final db = await database;
    final maps = await db.query(
      'visit_records',
      where: 'tree_id = ?',
      whereArgs: [treeId],
      orderBy: 'visited_at DESC',
    );
    return maps.map((m) => VisitRecord.fromMap(m)).toList();
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
