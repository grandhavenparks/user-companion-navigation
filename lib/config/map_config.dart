import 'dart:ui';

/// Offline basemap configuration (Protomaps vector tiles bundled as MBTiles).
class MapConfig {
  MapConfig._();

  /// Written by `tools/build_map.py`.
  static const String basemapAsset = 'assets/map/basemap.mbtiles';
  static const String manifestAsset = 'assets/map/map_manifest.json';

  /// Protomaps "light" style, version 4 (CC0), shipped with the app.
  static const String styleAsset = 'assets/map/protomaps_light_v4.json';

  /// Source id used by the style's layers.
  static const String tileSourceId = 'protomaps';

  /// Vector data stops at z15; tiles are rendered sharply up to [maxZoom].
  static const double minZoom = 3;
  static const double maxZoom = 24;

  /// Zoom used when the map starts following the user.
  static const double followZoom = 18;

  /// Upper bound when fitting the camera to a park or area.
  static const double fitMaxZoom = 19;

  static const String attribution = '© OpenStreetMap contributors, Protomaps';

  /// Shown where no map data exists (outside the bundled extract).
  static const Color backgroundColor = Color(0xFFE0E0E0);
}
