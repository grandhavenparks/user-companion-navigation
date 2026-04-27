/// Validates GeoJSON structure expected from Website Output (FeatureCollection of Points).
bool isValidGeoJSON(Map<String, dynamic> json) {
  if (json['type'] != 'FeatureCollection') return false;
  final features = json['features'];
  if (features is! List || features.isEmpty) return false;
  for (final f in features) {
    if (f is! Map<String, dynamic>) return false;
    if (f['type'] != 'Feature') return false;
    final geom = f['geometry'];
    if (geom is! Map<String, dynamic> || geom['type'] != 'Point') return false;
    final coords = geom['coordinates'];
    if (coords is! List || coords.length < 2) return false;
    final lon = coords[0], lat = coords[1];
    if (lon is! num || lat is! num) return false;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return false;
  }
  return true;
}
