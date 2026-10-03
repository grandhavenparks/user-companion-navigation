import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Custom tile provider that loads tiles from SQLite databases
class OfflineTileProvider extends TileProvider {
  final String dbPath;
  Database? _database;

  OfflineTileProvider(this.dbPath);

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    final appDir = await getApplicationDocumentsDirectory();
    final fullPath = path.join(appDir.path, 'fmtc', dbPath);
    
    _database = await openDatabase(fullPath, readOnly: true);
    return _database!;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImageProvider(
      coordinates: coordinates,
      provider: this,
    );
  }

  Future<Uint8List?> getTileData(int zoom, int x, int y) async {
    try {
      final db = await database;
      final result = await db.query(
        'tiles',
        columns: ['data'],
        where: 'zoom = ? AND x = ? AND y = ?',
        whereArgs: [zoom, x, y],
      );

      if (result.isNotEmpty) {
        return result.first['data'] as Uint8List;
      }
    } catch (e) {
      print('Error loading tile $zoom/$x/$y from $dbPath: $e');
    }
    return null;
  }

  @override
  void dispose() {
    _database?.close();
    super.dispose();
  }
}

class OfflineTileImageProvider extends ImageProvider<OfflineTileImageProvider> {
  final TileCoordinates coordinates;
  final OfflineTileProvider provider;

  const OfflineTileImageProvider({
    required this.coordinates,
    required this.provider,
  });

  @override
  ImageStreamCompleter loadImage(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final tileData = await provider.getTileData(
      coordinates.z.toInt(),
      coordinates.x.toInt(),
      coordinates.y.toInt(),
    );

    if (tileData != null) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(tileData);
      return decode(buffer);
    }

    // Return empty 1x1 transparent image if tile not found
    final emptyTile = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 image
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT chunk
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND chunk
      0x42, 0x60, 0x82,
    ]);

    final buffer = await ui.ImmutableBuffer.fromUint8List(emptyTile);
    return decode(buffer);
  }

  @override
  Future<OfflineTileImageProvider> obtainKey(covariant ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OfflineTileImageProvider &&
        other.coordinates == coordinates &&
        other.provider == provider;
  }

  @override
  int get hashCode => Object.hash(coordinates, provider);
}
