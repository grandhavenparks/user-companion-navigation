import 'package:flutter_map/flutter_map.dart';

import '../config/map_config.dart';
import '../config/tile_zoom_limits.dart';

/// Available map tile layers.
///
/// OSM was removed: `tile.openstreetmap.org`'s usage policy forbids bundled
/// offline prefetch, and our bundled `osm_tiles.db` was largely populated with
/// the "Access blocked" warning PNG instead of real tiles. Only topo is wired
/// up. To add another layer in the future, add a value to this enum and a
/// matching `case` in the two switches below.
enum MapLayerType { topo }

TileLayer tileLayerForType(MapLayerType type, TileZoomLimits limits) {
  switch (type) {
    case MapLayerType.topo:
      return MapConfig.openTopoMapLayer(limits);
  }
}

double maxZoomForLayerType(MapLayerType type, TileZoomLimits limits) {
  switch (type) {
    case MapLayerType.topo:
      return limits.maxZoomTopo.toDouble();
  }
}