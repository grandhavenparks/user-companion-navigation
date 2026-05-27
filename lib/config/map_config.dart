import 'package:flutter_map/flutter_map.dart';

import '../services/map_cache_service.dart';
import 'tile_zoom_limits.dart';

/// Map tile layer configuration.
///
/// Only OpenTopoMap is configured here. OSM was removed because
/// `tile.openstreetmap.org` blocks bundled offline prefetch (see
/// `map_layer_selector.dart` for the longer note). The bundled
/// `assets/tiles/osm_tiles.db` is no longer imported or referenced from
/// runtime; the asset file is intentionally kept on disk for now.
class MapConfig {
  MapConfig._();

  static const String topoAttribution =
      '© <a href="https://opentopomap.org/">OpenTopoMap</a> contributors';

  static const double tileSize = 256.0;
  static const int panBuffer = 1;

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