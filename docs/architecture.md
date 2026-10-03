# Architecture

## Stack

- Flutter (Dart >= 3.10), Riverpod 2 for state.
- Map: `flutter_map` 8 + `vector_map_tiles` (raster mode: vector tiles are
  rendered to images on background isolates, best frame rate) reading
  Protomaps vector tiles from a bundled MBTiles file through sqflite
  (`MbTilesVectorTileProvider` in `lib/services/basemap_service.dart`).
- Local DB: `sqflite` (`AppConfig.databaseName`).
- GPS: `geolocator` (fused provider, 1 s interval by default).

## Startup (`lib/main.dart`)

1. Load `SharedPreferences` and inject it via `sharedPreferencesProvider`.
2. `runApp` with `ProviderScope`; `HomeScreen` watches `basemapProvider`,
   which installs (once per map build) and opens the offline map.

## Screens

| Screen | Role |
|--------|------|
| `HomeScreen` | Open park map, warning only if the offline map is missing/broken, datasets (enable/disable/delete), Import CSV with report, export/clear visited. |
| `ParkMapScreen` | Shows the safety reminder first (`lib/widgets/safety_prompt.dart`); only after **Okay** does it build the map view and start GPS. Then: park selector, vector basemap, park areas, points, route, user position, navigation card, status banners (GPS off, permission, approximate location, missing map). Keeps the screen on while navigating. |
| `TreeDetailScreen` | Point info (name, classification, confidence, coordinates with copy, park membership, distance/bearing) and Mark visited / not visited. |
| `SettingsScreen` | Feet/metres, GPS interval, arrival radius, offline map info. |

## Providers (`lib/providers/`)

- `settingsProvider` - user settings (shared_preferences).
- `basemapProvider` - offline map (`Basemap`: theme + tile providers).
- `parksProvider`, `selectedParkIdProvider`, `selectedParkProvider` - parks
  discovered from the asset manifest.
- `datasetsProvider`, `datasetStatsProvider`, `datasetPointsProvider(id)`,
  `treeByIdProvider` - database (points of a dataset stay cached in memory).
- `run_provider.dart`: `activeRunProvider` (one run on the map; default the
  newest), `activeClusterSetProvider`, `clusterViewProvider` (remembered),
  `runPointsProvider`, `clusterPointsProvider` and `visiblePointsProvider`
  (what the map draws and navigates). The map watches both point sets so the
  view switch never waits for the database.
- `parkTreesProvider` - visible points split by the selected park's areas;
  a cluster whose average position falls just outside still belongs to the
  area of its trees (`Tree.parkId` / `Tree.areaIndex`).
- `locationControllerProvider` - GPS stream lifecycle (permission, service
  status, approximate-location detection, pause in background, restart on
  resume or interval change). Auto-disposed when the map closes.
- `navigationProvider` - `NavigationState` recomputed on every fix / data
  change via the pure function `computeNavigation`. One memory per view
  (points / clusters), so each view keeps its own target; the arrival radius
  is 10 m for points and 25 m for clusters (Settings).

## Clusters (`lib/services/cluster_service.dart`)

- Same grid as the old app: 100 m cells fixed to latitude/longitude lines,
  cell width from the mean latitude; all points of a cell merge (any
  classification, visited or not) at their average position; label = most
  common classification; no confidence; largest first, named
  "Cluster N (k trees)". Cells are additionally split by park area.
- Stored like an import: a dataset with `kind = clusters` and
  `parent_id = run`, points with `member_count`, `members`, `park_id`,
  `area_index`. Creating or importing replaces the run's previous set.

## Navigation logic

- Navigation is active only when the user is inside an area of the selected
  park; only unvisited points of that same area are routed.
- Target = nearest unvisited point (`chooseTarget`). An existing target is
  kept until another point is closer by
  `max(5 m, 20 % of the current distance, half the GPS accuracy)`. This makes
  the target follow the user when they wander off without marking a point,
  without flickering between two equidistant points.
- The remaining points are ordered as an open route starting at the target
  (nearest neighbour + 2-opt, start fixed, end free). The order is recomputed
  only when the target or the set of unvisited points changes.
- `arrived` = within the arrival radius (Settings, default 10 m).

All of this is covered by unit tests in `test/`.
