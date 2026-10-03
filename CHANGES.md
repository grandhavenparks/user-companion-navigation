# Changes

## 1.2.0

- App name **User Navigation Companion**; Android application id and
  namespace `com.user_navigation_companion` (`MainActivity.kt` moved to
  `android/app/src/main/kotlin/com/user_navigation_companion/`).
- Safety reminder before navigation: "Be safe and mindful of your
  surroundings during navigation." with **Okay**. The map, GPS and the
  location permission request start only after Okay; back closes the page.
- Home screen no longer shows the "Offline map ready" line; it only warns
  when the bundled map is missing or cannot be opened.
- `.gitignore`: `.venv/`, `__pycache__/`.
- `tools/remove_obsolete_files.sh`: removes the old Kotlin package folder and
  no longer deletes `pubspec.lock`.
- Includes your fixes from 1.1 testing (`(_, _)` listener,
  non-const `StrokePattern.dashed`, `didChangeAppLifecycleState(state)`,
  unused `dart:typed_data` import).

## 1.1.0

### How to apply this zip

```bash
cd ~/Documents/Repos/work/edge_forestry_mobile
git init && git add -A && git commit -m "baseline 1.0"     # once, so you can diff/revert
unzip -o ~/Downloads/edge_forestry_mobile_v1.1.zip -d .
bash tools/remove_obsolete_files.sh
brew install pmtiles
python3 -m pip install -r tools/requirements.txt
python3 tools/build_map.py
flutter clean && flutter pub get && flutter analyze && flutter test
adb uninstall com.edgeforestry
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### New

- Offline map switched to **Protomaps** vector tiles (free, keyless, built by
  `tools/build_map.py` with `pmtiles extract`), rendered sharply up to **zoom 24**.
- Navigation per park area: nearest unvisited point with hysteresis, open
  route ending at the last unvisited point, re-targets to the nearest point
  when you wander off, Arrived -> Mark visited (with Undo).
- Smooth position: 1 s GPS, gliding marker, accuracy circle, follow mode,
  screen kept on while navigating, fresh fix and re-route after screen on.
- CSV import accepts many column names/formats and shows an import report;
  filename/classification/confidence are stored and shown.
- Parks: all `parks/*.geojson` discovered automatically; MultiPolygon,
  multiple features and holes supported.
- Settings: GPS interval and arrival radius are editable and used; feet/metres
  is applied everywhere.
- Unit tests for CSV parsing, parks, route planning, navigation, map helpers.

### Faults fixed

| Fault | Fix |
|-------|-----|
| `CardTheme` build error on Flutter 3.41 | `CardThemeData` |
| `test/widget_test.dart` referenced non-existent `MyApp` | replaced by real unit tests |
| Old plugins / Gradle / AGP / Kotlin vs Flutter 3.41 | dependencies and Android build files updated to the 3.41 templates |
| Unused `flutter_map_tile_caching` (ObjectBox native libs, GPL-3) | removed |
| `download_tiles.py` bulk-downloaded OSM tiles z14-18 with a spoofed Referer (OSM policy) | replaced by Protomaps extract |
| Zoom capped at 22 in code and at the tile max (18) on the map | map zoom 3-24, data overzoomed from z15 |
| Only the first feature of a park file was used (Bass River boundary pointed at the wrong area) | every polygon is an area |
| Hard-coded park list | asset-manifest discovery |
| Ray casting double-counted vertices | half-open crossing rule |
| New tile provider (and DB handle) created on every GPS update | basemap opened once per session |
| Tile DBs copied through RAM on every launch | copied only when the map build changes |
| GPS off made the whole map disappear | map stays; banner with "Turn on" |
| Approximate-only location not detected | banner with link to settings |
| Route recomputed from scratch on every fix; target could flicker | stable target with hysteresis; route re-ordered only when needed |
| Route Progress always showed "0 of N visited" | counts visited points in the area |
| O(n³) orange outline polygon on the UI thread; duplicate markers | removed; one marker per point |
| Toggling a dataset did not refresh the map | providers invalidated |
| Feet setting and GPS interval were not used; arrival threshold unused | wired in |
| User marker drawn under the points | drawn on top |
| CSV: no quoting, no other delimiters/names, data columns dropped, silent skips, NaN accepted | new parser (see docs/data-and-offline.md) |
| Import not transactional | single transaction, parsed in a background isolate |
| Export had only lat/lon | adds filename, time, dataset, classification, confidence, notes |
| `formatBearing` could show 360° | wraps to 0° |
| Health classification text could colour an oak wilt point "healthy" | colours no longer depend on classification |

### Files

- Removed (run `bash tools/remove_obsolete_files.sh`): `download_tiles.py`,
  `assets/tiles/`, `pubspec.lock`, `test/widget_test.dart`, and in `lib/`:
  `config/tile_zoom_limits.dart`, `providers/tile_zoom_limits_provider.dart`,
  `providers/visit_provider.dart`, `providers/visit_repository_provider.dart`,
  `repositories/visit_repository.dart`, `models/visit_record.dart`,
  `services/geojson_parser_service.dart`, `services/map_cache_service.dart`,
  `services/offline_tile_provider.dart`, `services/tile_import_service.dart`,
  `services/points_service.dart`, `services/park_route_service.dart`,
  `utils/geojson_validator.dart`, `utils/permissions_handler.dart`,
  `widgets/map_layer_selector.dart`.
- No longer bundled (files kept): `points/`, `assets/sample/`.
- Unchanged: `lib/models/dataset.dart`, `lib/providers/database_provider.dart`,
  `dataset_provider.dart`, `dataset_repository_provider.dart`,
  `tree_repository_provider.dart`, `trees_provider.dart`, `parks/*`, `ios/*`,
  Android resources, `analysis_options.yaml`, `.gitignore`.
