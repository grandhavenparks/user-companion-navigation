import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Service to import pre-downloaded tiles from assets into FMTC
class TileImportService {
  TileImportService._();
  static final TileImportService instance = TileImportService._();

  /// Import tiles from assets/tiles/*.db to app storage for FMTC.
  /// Replaces any existing `fmtc/*.db` on every run so updated bundled DBs are used.
  Future<void> importTilesFromAssets() async {
    final appDir = await getApplicationDocumentsDirectory();
    final fmtcDir = Directory(path.join(appDir.path, 'fmtc'));
    
    if (!await fmtcDir.exists()) {
      await fmtcDir.create(recursive: true);
    }

    // Import OSM tiles
    await _importDatabase(
      assetPath: 'assets/tiles/osm_tiles.db',
      targetPath: path.join(fmtcDir.path, 'osm_tiles.db'),
      storeName: 'osm_tiles',
    );

    // Import Topo tiles
    await _importDatabase(
      assetPath: 'assets/tiles/topo_tiles.db',
      targetPath: path.join(fmtcDir.path, 'topo_tiles.db'),
      storeName: 'topo_tiles',
    );
  }

  Future<void> _importDatabase({
    required String assetPath,
    required String targetPath,
    required String storeName,
  }) async {
    try {
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      print('Importing $storeName from assets...');
      
      // Load database from assets
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();
      
      // Write to app storage
      await targetFile.writeAsBytes(bytes, flush: true);
      
      final size = await targetFile.length();
      print('✓ Imported $storeName: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Verify database integrity
      final db = await openDatabase(targetPath, readOnly: true);
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM tiles')
      );
      await db.close();
      
      print('  Contains ${count ?? 0} tiles');
      
    } catch (e) {
      print('Error importing $storeName: $e');
      // Continue - app will fall back to network
    }
  }
}
