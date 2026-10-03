import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../config/map_config.dart';

/// Contents of `assets/map/map_manifest.json` (written by tools/build_map.py).
@immutable
class MapManifest {
  const MapManifest({
    required this.buildId,
    required this.minZoom,
    required this.maxZoom,
    this.createdUtc,
    this.source,
    this.tileCount,
    this.sizeBytes,
    this.bufferMeters,
    this.parkNames = const [],
    this.attribution = MapConfig.attribution,
  });

  factory MapManifest.fromJson(Map<String, dynamic> json) {
    final parks = (json['parks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((park) => (park['name'] ?? park['file'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
    return MapManifest(
      buildId: (json['build_id'] ?? '').toString(),
      minZoom: (json['min_zoom'] as num?)?.toInt() ?? 0,
      maxZoom: (json['max_zoom'] as num?)?.toInt() ?? 15,
      createdUtc: DateTime.tryParse((json['created_utc'] ?? '').toString()),
      source: json['source']?.toString(),
      tileCount: (json['tile_count'] as num?)?.toInt(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      bufferMeters: (json['buffer_m'] as num?)?.toDouble(),
      parkNames: parks,
      attribution: json['attribution']?.toString() ?? MapConfig.attribution,
    );
  }

  final String buildId;
  final int minZoom;
  final int maxZoom;
  final DateTime? createdUtc;
  final String? source;
  final int? tileCount;
  final int? sizeBytes;
  final double? bufferMeters;
  final List<String> parkNames;
  final String attribution;
}

enum BasemapStatus { ready, missing, failed }

/// The offline basemap ready to hand to a `VectorTileLayer`.
@immutable
class Basemap {
  const Basemap._({
    required this.status,
    this.manifest,
    this.theme,
    this.tileProviders,
    this.message,
  });

  const Basemap.missing(String message)
      : this._(status: BasemapStatus.missing, message: message);

  const Basemap.failed(String message, {MapManifest? manifest})
      : this._(status: BasemapStatus.failed, message: message, manifest: manifest);

  const Basemap.ready({
    required MapManifest manifest,
    required vtr.Theme theme,
    required TileProviders tileProviders,
  }) : this._(
          status: BasemapStatus.ready,
          manifest: manifest,
          theme: theme,
          tileProviders: tileProviders,
        );

  final BasemapStatus status;
  final MapManifest? manifest;
  final vtr.Theme? theme;
  final TileProviders? tileProviders;
  final String? message;

  bool get isReady => status == BasemapStatus.ready;
}

/// Installs and opens the bundled MBTiles basemap.
///
/// The database is copied out of the APK only when the bundled build differs
/// from the installed one (compared by `build_id`), not on every start, and
/// it is opened once and shared for the whole app session.
class BasemapService {
  BasemapService._();

  static final BasemapService instance = BasemapService._();

  Future<Basemap>? _loading;

  Future<Basemap> load() => _loading ??= _load();

  Future<Basemap> _load() async {
    await _removeLegacyTileCopies();

    final MapManifest manifest;
    try {
      final raw = await rootBundle.loadString(MapConfig.manifestAsset);
      manifest = MapManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Basemap.missing(
          'No offline map is bundled. Run tools/build_map.py, then rebuild the app.');
    }
    if (manifest.buildId.isEmpty) {
      return const Basemap.missing(
          'map_manifest.json has no build_id. Re-run tools/build_map.py.');
    }

    try {
      final file = await _install(manifest);
      final db = await openDatabase(file.path, readOnly: true);
      final styleJson = jsonDecode(
              await rootBundle.loadString(MapConfig.styleAsset))
          as Map<String, dynamic>;
      final theme = vtr.ThemeReader().read(styleJson);
      final provider = MbTilesVectorTileProvider(
        db,
        minimumZoom: manifest.minZoom,
        maximumZoom: manifest.maxZoom,
      );
      return Basemap.ready(
        manifest: manifest,
        theme: theme,
        tileProviders: TileProviders({MapConfig.tileSourceId: provider}),
      );
    } catch (e) {
      return Basemap.failed('The offline map could not be opened: $e',
          manifest: manifest);
    }
  }

  Future<File> _install(MapManifest manifest) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'basemap'));
    await dir.create(recursive: true);
    final dbFile = File(p.join(dir.path, 'basemap.mbtiles'));
    final stampFile = File(p.join(dir.path, 'build_id.txt'));

    final installedId =
        await stampFile.exists() ? (await stampFile.readAsString()).trim() : null;
    if (installedId == manifest.buildId && await dbFile.exists()) {
      return dbFile;
    }

    debugPrint('Basemap: installing build ${manifest.buildId}');
    final data = await rootBundle.load(MapConfig.basemapAsset);
    final tmp = File('${dbFile.path}.tmp');
    await tmp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    if (await dbFile.exists()) await dbFile.delete();
    await tmp.rename(dbFile.path);
    await stampFile.writeAsString(manifest.buildId, flush: true);
    return dbFile;
  }

  /// Version 1.0 copied raster tile databases to Documents/fmtc on every
  /// start. They are not used any more.
  Future<void> _removeLegacyTileCopies() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacy = Directory(p.join(docs.path, 'fmtc'));
      if (await legacy.exists()) await legacy.delete(recursive: true);
    } catch (e) {
      debugPrint('Basemap: could not remove legacy tiles: $e');
    }
  }
}

/// Serves Mapbox Vector Tiles from an MBTiles (SQLite) file.
class MbTilesVectorTileProvider extends VectorTileProvider {
  MbTilesVectorTileProvider(
    this._db, {
    required this.minimumZoom,
    required this.maximumZoom,
  });

  final Database _db;

  @override
  final int minimumZoom;

  @override
  final int maximumZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  TileProviderType get type => TileProviderType.vector;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final rows = await _db.rawQuery(
      'SELECT tile_data FROM tiles '
      'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1',
      [tile.z, tile.x, tmsRow(tile.z, tile.y)],
    );
    if (rows.isEmpty) {
      throw ProviderException(
        message: 'No offline tile for $tile',
        statusCode: 404,
        retryable: Retryable.none,
      );
    }
    final data = rows.first['tile_data'];
    if (data is! Uint8List) {
      throw ProviderException(
        message: 'Unexpected tile data for $tile',
        retryable: Retryable.none,
      );
    }
    return decodeTileData(data);
  }
}

/// MBTiles stores rows in TMS order (y counted from the bottom).
int tmsRow(int zoom, int y) => (1 << zoom) - 1 - y;

/// Protomaps tiles are gzip-compressed inside the archive.
Uint8List decodeTileData(Uint8List data) {
  if (data.length > 2 && data[0] == 0x1f && data[1] == 0x8b) {
    return Uint8List.fromList(gzip.decode(data));
  }
  return data;
}