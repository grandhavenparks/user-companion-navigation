# Data model and offline assets

## SQLite (`DatabaseService`)

- **`datasets`**: imported dataset metadata (id, name, tree count, enabled flag, etc.).
- **`trees`**: points (`latitude`, `longitude`, `filename`, optional ML fields, `visited`, `visited_at`, `visit_notes`).
- **`visit_records`**: legacy table for older visit logging; **clear visited** on home also deletes these rows when resetting flags.

Repositories: `DatasetRepository`, `TreeRepository`, `VisitRepository`.

## CSV import (home screen)

- User picks a `.csv` via `file_picker`.
- Parser: `parsePointsCsv` in `csv_points_parser_service.dart`.
- **Required headers**: a latitude column (`latitude` / `lat`) and a longitude column (`longitude` / `lng` / `lon` / `long`).
- Each valid row becomes a `Tree` linked to a new `Dataset`; default `predictedClass` for CSV points is `sick` (used for marker coloring).

## Park boundaries

- Shipped as **assets**: `parks/*.geojson` (see `pubspec.yaml` `assets: - parks/`).
- `ParkService._parkFiles` lists which files to load; IDs are derived from filenames (without `.geojson`).
- If a file is listed in code but missing from `parks/`, that asset load fails at runtime (remove the entry or add the file).

## Offline map tiles

- **Bundled**: `assets/tiles/osm_tiles.db`, `topo_tiles.db`, and `tile_zoom_config.json`.
- **Regeneration**: Python script `download_tiles.py` at the project root (see **Offline tiles** in root `README.md`). It writes SQLite DBs and `tile_zoom_config.json` under `assets/tiles/` from `MIN_ZOOM`, `MAX_ZOOM`, `MAX_ZOOM_TOPO` in the script.
- **Runtime**: `TileImportService` copies those DBs into `getApplicationDocumentsDirectory()/fmtc/` on every app start.
- **Rendering**: `MapConfig` + `OfflineTileProvider` read tiles by `(zoom, x, y)` from SQLite; missing tiles degrade to a transparent placeholder.

## Visited points export

- **Export visited points (CSV)** on home: `getVisitedTrees()` → `share_plus` shares a CSV with header `latitude,longitude`.
- Optional dialog after share: **clear** all visited flags (and `visit_records`).
- **Clear visited marks** on home: same clear without exporting.

## Map zoom limits

- `TileZoomCache` / `tile_zoom_limits_provider` supply min/max zoom per layer so the map stays consistent with what was downloaded (defaults 14–18 OSM, 17 topo if JSON missing).
