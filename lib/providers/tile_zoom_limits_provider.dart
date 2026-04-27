import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/tile_zoom_limits.dart';

/// Zoom limits from `assets/tiles/tile_zoom_config.json` (see `download_tiles.py`).
final tileZoomLimitsProvider = Provider<TileZoomLimits>((ref) => TileZoomCache.limits);
