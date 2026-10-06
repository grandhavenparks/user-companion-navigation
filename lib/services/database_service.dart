import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../models/dataset.dart';
import '../models/tree.dart';

/// Number of points and visited points in a dataset.
class DatasetStats {
  const DatasetStats({required this.total, required this.visited});

  final int total;
  final int visited;
}

/// SQLite database for runs (imported CSVs), cluster sets, points and visit
/// state.
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
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE datasets ADD COLUMN kind TEXT NOT NULL DEFAULT 'points'");
      await db.execute('ALTER TABLE datasets ADD COLUMN parent_id TEXT');
      await db.execute('ALTER TABLE trees ADD COLUMN member_count INTEGER');
      await db.execute('ALTER TABLE trees ADD COLUMN members TEXT');
      await db.execute('ALTER TABLE trees ADD COLUMN park_id TEXT');
      await db.execute('ALTER TABLE trees ADD COLUMN area_index INTEGER');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_datasets_parent ON datasets(parent_id)');
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
        enabled INTEGER NOT NULL DEFAULT 1,
        kind TEXT NOT NULL DEFAULT 'points',
        parent_id TEXT
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
        member_count INTEGER,
        members TEXT,
        park_id TEXT,
        area_index INTEGER,
        FOREIGN KEY (dataset_id) REFERENCES datasets (id)
      )
    ''');
    // Kept for databases created by older versions.
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
    await db.execute('CREATE INDEX idx_datasets_parent ON datasets(parent_id)');
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

  /// Replaces the cluster set of run [runId] with [clusterSet] (created in
  /// the app or imported from a cluster CSV). Old clusters and their visited
  /// marks are removed in the same transaction.
  Future<void> replaceClusterSet(
    String runId,
    Dataset clusterSet,
    List<Tree> clusters,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await _deleteClusterSetsOf(txn, runId);
      await txn.insert('datasets', clusterSet.toMap());
      final batch = txn.batch();
      for (final c in clusters) {
        batch.insert('trees', c.toMap());
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _deleteClusterSetsOf(Transaction txn, String runId) async {
    await txn.rawDelete(
      'DELETE FROM trees WHERE dataset_id IN '
      "(SELECT id FROM datasets WHERE kind = 'clusters' AND parent_id = ?)",
      [runId],
    );
    await txn.delete(
      'datasets',
      where: "kind = 'clusters' AND parent_id = ?",
      whereArgs: [runId],
    );
  }

  Future<List<Dataset>> getAllDatasets() async {
    final db = await database;
    final maps = await db.query('datasets', orderBy: 'imported_at DESC');
    return maps.map(Dataset.fromMap).toList();
  }

  /// Deletes a dataset. Deleting a run also deletes its cluster set.
  Future<void> deleteDataset(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM visit_records WHERE tree_id IN '
        '(SELECT id FROM trees WHERE dataset_id = ?)',
        [id],
      );
      await _deleteClusterSetsOf(txn, id);
      await txn.delete('trees', where: 'dataset_id = ?', whereArgs: [id]);
      await txn.delete('datasets', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Points and visited points per dataset id.
  Future<Map<String, DatasetStats>> getDatasetStats() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT dataset_id, COUNT(*) AS total, SUM(visited) AS visited '
      'FROM trees GROUP BY dataset_id',
    );
    return {
      for (final r in rows)
        r['dataset_id'] as String: DatasetStats(
          total: (r['total'] as num?)?.toInt() ?? 0,
          visited: (r['visited'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  // --- Points --------------------------------------------------------------

  Future<List<Tree>> getTreesByDataset(String datasetId) async {
    final db = await database;
    final maps = await db.query(
      'trees',
      where: 'dataset_id = ?',
      whereArgs: [datasetId],
    );
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

  /// Visited points of one dataset, newest first.
  Future<List<Tree>> getVisitedTreesByDataset(String datasetId) async {
    final db = await database;
    final maps = await db.query(
      'trees',
      where: 'dataset_id = ? AND visited = 1',
      whereArgs: [datasetId],
      orderBy: 'visited_at DESC',
    );
    return maps.map(Tree.fromMap).toList();
  }

  /// Unmarks every visited point of one dataset.
  Future<void> clearVisitedForDataset(String datasetId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE trees SET visited = 0, visited_at = NULL, visit_notes = NULL '
      'WHERE dataset_id = ? AND visited = 1',
      [datasetId],
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
  }
}
