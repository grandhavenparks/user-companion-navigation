import 'package:flutter_map/flutter_map.dart';
import 'offline_tile_provider.dart';

class MapCacheService {
  MapCacheService._();
  static final MapCacheService instance = MapCacheService._();

  static const String osmStoreName = 'osm_tiles.db';
  static const String topoStoreName = 'topo_tiles.db';

  Future<void> init() async {
    // Initialization handled by TileImportService
    print('MapCacheService initialized');
  }

  TileProvider getTileProvider(String storeName) {
    // Return custom offline tile provider that reads from SQLite
    return OfflineTileProvider(storeName);
  }

  Future<void> downloadRegion({
    required String storeName,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required void Function(dynamic) onProgress,
  }) async {
    throw UnimplementedError('Use download_tiles.py script to download tiles');
  }

  Future<dynamic> getStats(String storeName) async {
    return null;
  }

  Future<void> clearCache(String storeName) async {
    // Not implemented for bundled tiles
  }
}
