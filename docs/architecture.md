# Architecture

## Stack

- **Flutter** (Dart SDK `>=3.2.0 <4.0.0`), **Riverpod** for state.
- **Maps**: `flutter_map` + `latlong2`. Raster layers use **OpenStreetMap** and **OpenTopoMap** URL templates; tiles are served from **SQLite** on disk via a custom `TileProvider` (see [data-and-offline.md](data-and-offline.md)).
- **Local DB**: `sqflite` (`AppConfig.databaseName`, version in `app_config.dart`).

## Startup (`lib/main.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `TileZoomCache.load()` — reads `assets/tiles/tile_zoom_config.json` (fallback constants in `tile_zoom_limits.dart` if missing).
3. `MapCacheService.instance.init()` — placeholder init.
4. `TileImportService.importTilesFromAssets()` — copies `assets/tiles/osm_tiles.db` and `topo_tiles.db` into app documents under `fmtc/`, **replacing** any existing files so bundled DBs always win.
5. `runApp` with `ProviderScope`, `HomeScreen` as home.

## Main screens

| Screen | Role |
|--------|------|
| `HomeScreen` | Lists **datasets** (CSV imports), toggles enabled, delete, **Import CSV** FAB, **Open Park Map**, **Export visited points (CSV)**, **Clear visited marks**, link to **Settings**. |
| `ParkMapScreen` | **Park** dropdown (from bundled park GeoJSON). Map appears only after a park is selected; otherwise a “No park selected” placeholder. Boundary, imported points (polygon + markers), route/navigation UI when applicable. |
| `TreeDetailScreen` | From a tree/point marker: **Mark visited** / **Mark not visited** (SQLite `trees.visited`). |
| `SettingsScreen` | `SharedPreferences`: distance in feet, GPS interval display (values persisted; interval wiring depends on location service usage). |

There is **no** separate “offline maps” screen in the current tree; offline tiles back the park map only.

## Notable providers (`lib/providers/`)

- `datasetsProvider` / `datasetRepositoryProvider` — datasets in SQLite.
- `enabledTreesProvider` / `treeRepositoryProvider` — trees from enabled datasets.
- `parksProvider` — loads parks from assets via `ParkService` (cached).
- `selectedParkProvider` — `StateProvider<Park?>` for the map screen.
- `parkTreesProvider`, `parkPointsProvider`, `parkRouteProvider`, `nextTreeProvider` — trees/points inside selected park, route logic (`ParkRouteService`).
- `tileZoomLimitsProvider` — map min/max zoom aligned with offline tile zoom config.

## GeoJSON in codebase

- **Park boundaries**: bundled under `parks/*.geojson`, loaded by `ParkService`.
- **Analysis GeoJSON for trees**: `geojson_parser_service.dart` and `pickAndReadGeoJSON()` exist; the **home screen import path uses CSV only** (`pickAndReadCSV` + `parsePointsCsv`). GeoJSON import is not exposed on the home FAB.
