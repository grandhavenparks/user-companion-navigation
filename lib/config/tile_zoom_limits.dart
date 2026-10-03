import 'dart:convert';

import 'package:flutter/services.dart';

/// Zoom limits bundled with offline tiles (written by `download_tiles.py` as `tile_zoom_config.json`).
class TileZoomLimits {
  const TileZoomLimits({
    required this.minZoom,
    required this.maxZoomOsm,
    required this.maxZoomTopo,
  });

  final int minZoom;
  final int maxZoomOsm;
  final int maxZoomTopo;

  static const TileZoomLimits fallback = TileZoomLimits(
    minZoom: 14,
    maxZoomOsm: 18,
    maxZoomTopo: 17,
  );

  static Future<TileZoomLimits> loadFromAssets() async {
    try {
      final raw = await rootBundle.loadString('assets/tiles/tile_zoom_config.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      final minZ = (map['min_zoom'] as num?)?.toInt() ?? fallback.minZoom;
      final osm = (map['max_zoom_osm'] as num?)?.toInt() ?? fallback.maxZoomOsm;
      final topo = (map['max_zoom_topo'] as num?)?.toInt() ?? fallback.maxZoomTopo;
      return TileZoomLimits(
        minZoom: minZ.clamp(1, 22),
        maxZoomOsm: osm.clamp(1, 22),
        maxZoomTopo: topo.clamp(1, 22),
      );
    } catch (_) {
      return fallback;
    }
  }

  double get minZoomForMap => minZoom.toDouble();
}

/// Loaded in [main] before [runApp] so maps read zoom limits synchronously.
class TileZoomCache {
  TileZoomCache._();

  static TileZoomLimits _value = TileZoomLimits.fallback;

  static TileZoomLimits get limits => _value;

  static Future<void> load() async {
    _value = await TileZoomLimits.loadFromAssets();
  }
}
