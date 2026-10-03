# User Navigation Companion

Android app id: `com.user_navigation_companion` (Flutter project folder and Dart
package are still named `edge_forestry_mobile`).

Offline-first Flutter app for walking to flagged trees (for example oak wilt
detections) inside park boundaries. The map, park boundaries and navigation
work with no network at all; everything is bundled in the APK.

## What it does

- **Import points (CSV)**: any results file with latitude/longitude columns.
  Many header spellings are recognised (`lat`, `Latitude`, `y`, `GPSLatitude`,
  `decimalLatitude`, `POINT_Y`, `"lat"`, a combined `coordinates` column or
  WKT `POINT(lon lat)`), as are comma/semicolon/tab files, decimal commas,
  degrees-minutes-seconds and N/S/E/W letters. `filename`, `classification`
  and `confidence` columns are kept. An import report lists skipped rows.
- **Offline map**: Protomaps (OpenStreetMap) vector tiles, sharp up to zoom 24.
- **Parks**: every `parks/*.geojson` is loaded automatically. A file may hold
  several polygons (MultiPolygon, several features, holes).
- **Safety reminder**: every time the navigation page opens, "Be safe and
  mindful of your surroundings during navigation." is shown first; the map,
  GPS and navigation start after **Okay** (back closes the page).
- **Navigation inside a park**: when you are inside a park area, the app
  guides you to the nearest unvisited point, then along an open route that
  ends at the last unvisited point. If you walk away without marking a point,
  the target switches to whichever point is now clearly nearest. Within the
  arrival radius a **Mark visited** button appears (with Undo).
  Points outside the park are shown in grey and never navigated.
- **Smooth GPS**: 1 s updates, the position marker glides between fixes and
  the map follows you (pan to stop following, tap the location button to
  resume). The screen stays on while navigating. GPS stops when the screen
  is off and the route is recomputed from a fresh fix when it comes back.
- **Export visited points** as CSV (filename, coordinates, time, dataset,
  classification, confidence) via the share sheet.

## Requirements (development Mac)

- Flutter 3.38+ (tested target: 3.41.6), JDK 17, Android SDK 36, NDK 28.2
  (Flutter downloads/uses `flutter.ndkVersion`).
- Map build: `brew install pmtiles`, then a virtual environment (Homebrew
  Python blocks system-wide pip installs):
  `python3 -m venv .venv && source .venv/bin/activate && python3 -m pip install -r tools/requirements.txt`.

## Build and install

```bash
cd edge_forestry_mobile

# 1. Offline map for every park in parks/ (needs internet, a few minutes)
source .venv/bin/activate          # venv holding the pmtiles Python package
python3 tools/build_map.py

# 2. Dependencies, checks, tests
flutter pub get
flutter analyze
flutter test

# 3. Release APK for the Pixel 4 (arm64) and install over USB
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Use a **release** build in the field: map rendering runs on background
isolates only in release/profile mode, so debug builds feel choppy.

## Adding a park

1. Draw the boundary (e.g. geojson.io) and save it as
   `parks/<ST>_<NNNN>_<CamelCaseName>.geojson` (any name works; a `name`
   property on the first feature overrides the file name).
2. `python3 tools/build_map.py`
3. Rebuild and reinstall the APK.

## Offline map details (`tools/build_map.py`)

- Source: the free Protomaps daily planet build (no API key). Only the bytes
  for your parks are downloaded by `pmtiles extract`.
- Region: each park area's bounding box plus `--buffer-m` (default 500 m).
- Zoom: vector data z0-15; the app renders it sharply up to z24.
- Output: `assets/map/basemap.mbtiles` + `assets/map/map_manifest.json`.
  The app copies the MBTiles out of the APK only when its `build_id` changes.
- Options: `--source <url|file>`, `--buffer-m`, `--maxzoom`, `--dry-run`,
  `--keep-pmtiles` (view `build/map/basemap.pmtiles` on https://pmtiles.io).

Attribution shown in the app: © OpenStreetMap contributors, Protomaps
(ODbL data; Protomaps styles are CC0).

## Documentation

| Document | Contents |
|----------|----------|
| [docs/architecture.md](docs/architecture.md) | Modules, providers, navigation logic |
| [docs/data-and-offline.md](docs/data-and-offline.md) | CSV import, parks, offline map, database |
| [docs/android.md](docs/android.md) | Toolchain versions, signing, install/uninstall |
| [CHANGES.md](CHANGES.md) | What changed in 1.1 and which faults were fixed |

## License

Add the license **Kowshid**!
