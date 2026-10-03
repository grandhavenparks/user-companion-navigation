# Data and offline assets

## CSV import (`lib/services/csv_points_parser_service.dart`)

- Encoding: UTF-8 (BOM allowed), falls back to Latin-1.
- Delimiter: detected from the header (comma, semicolon, tab, pipe).
- Quoting: RFC 4180 (quoted fields, doubled quotes, separators and line
  breaks inside quotes).
- Coordinate columns (case, spaces, punctuation and units in brackets are
  ignored): `latitude lat y lat_dd decimalLatitude gps_lat GPSLatitude
  lat_wgs84 POINT_Y ...` and `longitude lon lng long x lon_dd
  decimalLongitude gps_lon GPSLongitude lon_wgs84 POINT_X ...`; any header
  containing a `lat`/`lon` word whose values are coordinates; or one combined
  column (`coordinates`, `latlon`, `location`, `geometry`, WKT `POINT(lon lat)`).
- Values: decimal degrees, decimal comma, DMS (`45°25'46.9"N`, `45 25 46.9`,
  `45d25m46.9s`), hemisphere letters (`93.76 W`, `N45.4`), Unicode minus.
- Validation: rows with lat/lon swapped are fixed; empty, unreadable,
  out-of-range and `0,0` rows are skipped and listed (with line numbers) in
  the import report. Only WGS84 degrees are supported (not UTM).
- Other columns kept: name (`filename`, `image`, `photo`, `name`, `id`, ...),
  `classification`, `confidence`/`score`, `description`/`notes`.
- Import runs in a background isolate and is saved in one transaction.

## Park boundaries (`parks/*.geojson`)

- Discovered through the Flutter asset manifest: no list in code.
- FeatureCollection, Feature or bare geometry; Polygon, MultiPolygon and
  GeometryCollection; every polygon becomes a park *area*; holes respected.
- Coordinates must be `[lon, lat]`; a swapped file is reported in the park
  selector's warning icon instead of silently failing.

## Offline map

- Built on the Mac by `tools/build_map.py` (see README) into
  `assets/map/basemap.mbtiles` + `map_manifest.json`; style
  `assets/map/protomaps_light_v4.json` (Protomaps light v4, CC0).
- At runtime `BasemapService` copies the MBTiles to app support storage only
  when the manifest `build_id` differs from the installed copy, opens it
  read-only once, and serves tiles (TMS rows, gzip decoded) to
  `vector_map_tiles`. Missing tiles outside the extract render as the grey
  background. Old `Documents/fmtc` tile copies from 1.0 are deleted.

## SQLite (`DatabaseService`)

- `datasets`, `trees` (points: name, coordinates, classification,
  confidence, visited, visited_at, visit_notes) and the legacy
  `visit_records` table (cleared with the visited flags).

## Visited export

- `filename,latitude,longitude,visited_at,dataset,classification,confidence,notes`
  shared via the system share sheet; optional clear afterwards. The file can be
  imported again.
