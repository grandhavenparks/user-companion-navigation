import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../models/tree.dart';

/// SQLite database for datasets, points and visit state.
class DatabaseService {
  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    final db = _db;
    if (db != null) return db;
    return _db = await (_opening ??= _init());
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
    // Kept for databases created by older versions; cleared together with
    // the visited flags.
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
    await db.execute('CREATE INDEX idx_trees_dataset ON trees(dataset_id)');
    await db.execute('CREATE INDEX idx_trees_visited ON trees(visited)');
    await db.execute(
        'CREATE INDEX idx_visit_records_tree ON visit_records(tree_id)');
  }

  // --- Datasets ------------------------------------------------------------

  /// Saves a dataset and all of its points in one transaction, so a failed
  /// import never leaves a half-imported dataset behind.
  Future<void> insertDatasetWithTrees(Dataset dataset, List<Tree> trees) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('datasets', dataset.toMap());
      final batch = txn.batch();
      for (final t in trees) {
        batch.insert('trees', t.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Dataset>> getAllDatasets() async {
    final db = await database;
    final maps = await db.query('datasets', orderBy: 'imported_at DESC');
    return maps.map(Dataset.fromMap).toList();
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
    await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM visit_records WHERE tree_id IN '
        '(SELECT id FROM trees WHERE dataset_id = ?)',
        [id],
      );
      await txn.delete('trees', where: 'dataset_id = ?', whereArgs: [id]);
      await txn.delete('datasets', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Points --------------------------------------------------------------

  Future<List<Tree>> getTreesFromEnabledDatasets() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM trees t
      INNER JOIN datasets d ON t.dataset_id = d.id
      WHERE d.enabled = 1
    ''');
    return maps.map(Tree.fromMap).toList();
  }

  Future<Tree?> getTreeById(String id) async {
    final db = await database;
    final maps = await db.query('trees', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Tree.fromMap(maps.first);
  }

  Future<void> updateTreeVisited(String treeId, bool visited) async {
    final db = await database;
    await db.update(
      'trees',
      {
        'visited': visited ? 1 : 0,
        'visited_at': visited ? DateTime.now().toIso8601String() : null,
        if (!visited) 'visit_notes': null,
      },
      where: 'id = ?',
      whereArgs: [treeId],
    );
  }

  /// All points marked visited (any dataset), newest first.
  Future<List<Tree>> getVisitedTrees() async {
    final db = await database;
    final maps = await db.query(
      'trees',
      where: 'visited = ?',
      whereArgs: [1],
      orderBy: 'visited_at DESC',
    );
    return maps.map(Tree.fromMap).toList();
  }

  /// Reset visited flags and remove legacy visit log rows.
  Future<void> clearAllVisitedState() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('visit_records');
      await txn.rawUpdate('''
        UPDATE trees SET visited = 0, visited_at = NULL, visit_notes = NULL
        WHERE visited = 1
      ''');
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
  }
}
