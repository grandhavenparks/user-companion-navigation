import 'package:flutter_map/flutter_map.dart';

import '../services/map_cache_service.dart';
import 'tile_zoom_limits.dart';

/// Map tile layer configuration - OpenStreetMap and OpenTopoMap (free, no API keys).
class MapConfig {
  MapConfig._();

  static const String osmAttribution =
      '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
  static const String topoAttribution =
      '© <a href="https://opentopomap.org/">OpenTopoMap</a> contributors';

  static const double tileSize = 256.0;
  static const int panBuffer = 1;

  /// OSM raster tiles — max zoom must match [TileZoomLimits.maxZoomOsm] from `download_tiles.py`.
  static TileLayer osmTileLayer(TileZoomLimits limits) {
    final maxZ = limits.maxZoomOsm;
    final z = maxZ.toDouble();
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.usercompanionnavigation',
      maxZoom: z,
      minZoom: limits.minZoomForMap,
      maxNativeZoom: maxZ,
      tileSize: tileSize,
      panBuffer: panBuffer,
      tileProvider: MapCacheService.instance.getTileProvider(MapCacheService.osmStoreName),
      errorTileCallback: (tile, error, stackTrace) {},
    );
  }

  /// OpenTopoMap — max zoom is at most [TileZoomLimits.maxZoomTopo] (server max 17).
  static TileLayer openTopoMapLayer(TileZoomLimits limits) {
    final maxZ = limits.maxZoomTopo;
    final z = maxZ.toDouble();
    return TileLayer(
      urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.usercompanionnavigation',
      maxZoom: z,
      minZoom: limits.minZoomForMap,
      maxNativeZoom: maxZ,
      tileSize: tileSize,
      panBuffer: panBuffer,
      tileProvider: MapCacheService.instance.getTileProvider(MapCacheService.topoStoreName),
      errorTileCallback: (tile, error, stackTrace) {},
    );
  }
}
