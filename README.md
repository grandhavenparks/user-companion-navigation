# User Companion Navigation App

Offline-first Flutter app for field navigation to flagged points in park areas: GPS on a map with bundled offline tiles, optional route hints inside a selected park, and local visit tracking.

## Technical documentation

Extra developer-focused notes (architecture, data model, Android toolchain) are in the `docs/` folder:

| Document | Contents |
|----------|----------|
| [docs/architecture.md](docs/architecture.md) | Startup, modules, navigation, Riverpod |
| [docs/data-and-offline.md](docs/data-and-offline.md) | SQLite, CSV import, park assets, offline tiles, visited export |
| [docs/android.md](docs/android.md) | Gradle / AGP / Kotlin / NDK versions for Android builds |

## Features

- **Import points (CSV)** — Pick a CSV with `latitude`/`lat` and `longitude`/`lng`/`lon` columns. Points are stored in SQLite as datasets you can enable or disable.
- **Park map** — Choose a **park** from bundled `parks/*.geojson` boundaries. The map (OSM or OpenTopo) uses **offline tiles** from assets; switch layers on the map. Until a park is selected, the map area shows a simple “no park selected” state.
- **Markers** — Imported points and classification-colored markers; tap a marker for **Mark visited** / **Mark not visited**.
- **Visited export** — From home: **Export visited points (CSV)** (lat/lon via system share), optional **clear** after export, and **Clear visited marks**.
- **Settings** — Distance in feet vs meters, GPS interval display, about.

## Requirements

- Flutter SDK (3.x), Dart `>=3.2.0`
- Android: use Java **17**, NDK **25.1.8937393** if the build requests it (see [`docs/android.md`](docs/android.md))

## Setup

```bash
cd user_companion_navigation_app
flutter pub get
flutter run
```

## Offline tiles (`download_tiles.py`)

The app ships **offline** OpenStreetMap and OpenTopoMap raster tiles as **SQLite** databases plus a small **JSON** file the Flutter app uses for min/max zoom. Operators regenerate these with the Python script at the project root.

### What the script does

1. **Writes** `assets/tiles/tile_zoom_config.json` from the script constants `MIN_ZOOM`, `MAX_ZOOM`, and `MAX_ZOOM_TOPO` (defaults: **14**, **18**, **17**). The Flutter app loads this at startup (`TileZoomCache`) so map zoom limits match the downloaded data.
2. **Creates/updates** `assets/tiles/osm_tiles.db` and `topo_tiles.db`, each with a `tiles` table (`zoom`, `x`, `y`, PNG `data`).
3. **Scans** `parks/*.geojson` — for each file’s first **Polygon** feature, computes a lat/lon bounding box and downloads every tile in the zoom range that intersects that box.
4. **Layers:** OSM tiles for `MIN_ZOOM`…`MAX_ZOOM`. OpenTopoMap for the same range but only while `zoom ≤ MAX_ZOOM_TOPO` (higher zooms are skipped; OTM does not serve them reliably).
5. **HTTP:** At least **1 second** between outbound requests (`MIN_SECONDS_BETWEEN_REQUESTS`). Uses a custom **User-Agent** and **Referer** headers (OSM/OTM policy). Optional env overrides: `TILE_REFERER_OSM`, `TILE_REFERER_TOPO`.
6. **Skips** re-downloading a tile if that `(zoom, x, y)` row already exists in the DB (no network call).

Licensing and attribution: the script prints OSM/OTM attribution text; your deployment must respect [OpenStreetMap](https://www.openstreetmap.org/copyright) and [OpenTopoMap](https://opentopomap.org/) terms.

### How to run

From the **`user_companion_navigation_app`** directory (where `parks/` and `assets/` live):

```bash
python3 download_tiles.py
```

Requires **Python 3** and network access. Duration depends on park size and zoom range (many tiles = long runs).

Adjust coverage or zoom by editing the constants at the top of `download_tiles.py` (`PARKS_DIR`, `OUTPUT_DIR`, `MIN_ZOOM`, `MAX_ZOOM`, `MAX_ZOOM_TOPO`), then re-run.

### App integration

On each cold start, `TileImportService` **copies** the bundled `assets/tiles/*.db` files into app storage (`fmtc/`), replacing any previous copy, so the device always matches what you built into the app. After you change assets, do a **full app restart** (stop and `flutter run` again—not only hot reload) so Flutter picks up new asset bundles.

## Permissions

- **Location** — Map and navigation context.
- **Storage / file access** — CSV import (platform-dependent).

## License

Add the license **Kowshid**!
