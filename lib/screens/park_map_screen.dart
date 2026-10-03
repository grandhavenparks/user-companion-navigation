import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../config/app_config.dart';
import '../config/map_config.dart';
import '../config/theme.dart';
import '../models/app_settings.dart';
import '../models/dataset.dart';
import '../models/park.dart';
import '../models/tree.dart';
import '../models/user_location.dart';
import '../providers/basemap_provider.dart';
import '../providers/dataset_repository_provider.dart';
import '../providers/location_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/park_provider.dart';
import '../providers/run_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../providers/trees_provider.dart';
import '../services/basemap_service.dart';
import '../services/cluster_service.dart';
import '../services/csv_points_parser_service.dart';
import '../services/file_import_service.dart';
import '../services/visited_points_export_service.dart';
import '../services/park_service.dart';
import '../services/screen_wake_service.dart';
import '../widgets/navigation_card.dart';
import '../widgets/safety_prompt.dart';
import '../widgets/status_banner.dart';
import '../widgets/tree_marker_widget.dart';
import '../widgets/user_location_layer.dart';
import 'tree_detail_screen.dart';

/// Reads a cluster CSV in a background isolate (cluster view only).
CsvPointsParseResult _parseClusterFile((PickedFile, String) input) =>
    parsePointsCsvBytes(
      input.$1.bytes,
      sourceName: input.$1.name,
      clusters: true,
      parentRunId: input.$2,
    );

/// Navigation page. The safety reminder is shown first; the map, GPS and
/// navigation only start after the user taps "Okay". Closing the reminder
/// with the back button leaves the page.
class ParkMapScreen extends ConsumerStatefulWidget {
  const ParkMapScreen({super.key});

  @override
  ConsumerState<ParkMapScreen> createState() => _ParkMapScreenState();
}

class _ParkMapScreenState extends ConsumerState<ParkMapScreen> {
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForSafety());
  }

  Future<void> _askForSafety() async {
    if (!mounted) return;
    final accepted = await showSafetyPrompt(context);
    if (!mounted) return;
    if (accepted) {
      // Every visit starts with no park selected; the user picks one.
      ref.read(selectedParkIdProvider.notifier).state = null;
      setState(() => _acknowledged = true);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_acknowledged) return const _ParkMapView();
    // Nothing behind the reminder: GPS has not started yet and the location
    // permission dialog cannot appear on top of it.
    return Scaffold(
      appBar: AppBar(title: const Text('Park map')),
      body: const SizedBox.expand(),
    );
  }
}

class _ParkMapView extends ConsumerStatefulWidget {
  const _ParkMapView();

  @override
  ConsumerState<_ParkMapView> createState() => _ParkMapViewState();
}

class _ParkMapViewState extends ConsumerState<_ParkMapView> {
  final MapController _mapController = MapController();
  bool _mapReady = false;

  /// Camera follows the (animated) GPS position. Dragging the map stops it;
  /// the location button or walking into the park starts it again.
  bool _follow = false;

  /// Whether we already decided to follow for the current park.
  bool _followDecided = false;

  @override
  void dispose() {
    unawaited(ScreenWake.instance.setKeepOn(false));
    _mapController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Park selection and camera
  // ---------------------------------------------------------------------------

  void _onLocation(UserLocation? location) {
    if (location == null) return;
    final park = ref.read(selectedParkProvider);
    if (park == null) return; // the user picks the park
    if (!_followDecided) {
      _followDecided = true;
      if (park.containsPoint(location.latitude, location.longitude)) {
        _startFollowing(location);
      }
    }
  }

  void _selectPark(Park park) {
    _followDecided = false;
    ref.read(selectedParkIdProvider.notifier).state = park.id;
    final location = ref.read(locationControllerProvider).location;
    if (location != null && park.containsPoint(location.latitude, location.longitude)) {
      _followDecided = true;
      _startFollowing(location);
    } else {
      setState(() => _follow = false);
      _fitToPark(park, location: location);
    }
    _explainEmptyPark(park);
  }

  /// When the chosen park holds none of the visible points, say where they are.
  void _explainEmptyPark(Park park) {
    final counts = ref.read(visibleParkCountsProvider);
    if ((counts[park.id] ?? 0) > 0) return;
    final clusterView = ref.read(clusterViewProvider);
    final noun = clusterView ? 'clusters' : 'points';
    final parks = ref.read(parksProvider).valueOrNull?.parks ?? const <Park>[];
    final elsewhere = [
      for (final p in parks)
        if ((counts[p.id] ?? 0) > 0) '${p.name} (${counts[p.id]})',
    ];
    if (ref.read(activeRunProvider) == null) return;
    _snack(elsewhere.isEmpty
        ? 'No $noun of this run are inside a bundled park.'
        : 'No $noun of this run in ${park.name}. They are in: '
            '${elsewhere.join(', ')}.');
  }

  GeoBounds _boundsFor(Park park, UserLocation? location) {
    if (location != null) {
      final area = park.areaIndexAt(location.latitude, location.longitude);
      if (area != null) return park.areas[area].bounds;
    }
    return park.bounds;
  }

  CameraFit _cameraFit(GeoBounds bounds) => CameraFit.bounds(
        bounds: LatLngBounds(bounds.southWest, bounds.northEast),
        padding: const EdgeInsets.fromLTRB(32, 220, 32, 96),
        maxZoom: MapConfig.fitMaxZoom,
      );

  void _fitToPark(Park park, {UserLocation? location}) {
    if (!_mapReady) return;
    _mapController.fitCamera(_cameraFit(_boundsFor(park, location)));
  }

  void _startFollowing(UserLocation location) {
    if (mounted) setState(() => _follow = true);
    if (!_mapReady) return;
    final zoom = math.max(_mapController.camera.zoom, MapConfig.followZoom);
    _mapController.move(location.position, zoom);
  }

  void _toggleFollow() {
    final location = ref.read(locationControllerProvider).location;
    if (_follow || location == null) {
      setState(() => _follow = false);
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No GPS position yet')),
        );
      }
      return;
    }
    _startFollowing(location);
  }

  void _onAnimatedMove(LatLng position) {
    if (!_follow || !_mapReady) return;
    _mapController.move(position, _mapController.camera.zoom);
  }

  // ---------------------------------------------------------------------------
  // Points
  // ---------------------------------------------------------------------------

  void _openPoint(Tree tree) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TreeDetailScreen(treeId: tree.id)),
    );
  }

  Future<void> _setVisited(Tree tree, bool visited) async {
    await ref.read(treeRepositoryProvider).setTreeVisited(tree.id, visited);
    refreshAfterVisitedChange(ref, tree);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(visited
              ? '${tree.filename} marked visited'
              : '${tree.filename} marked not visited'),
          action: visited
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _setVisited(tree, false),
                )
              : null,
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // Point / cluster view
  // ---------------------------------------------------------------------------

  /// Switching is instant: both point sets are already in memory and each
  /// view keeps its own navigation target.
  void _toggleClusterView() {
    final next = !ref.read(clusterViewProvider);
    ref.read(settingsProvider.notifier).setClusterView(next);
    final run = ref.read(activeRunProvider);
    final message = run == null
        ? (next ? 'Cluster view' : 'Point view')
        : next
            ? (ref.read(activeClusterSetProvider) == null
                ? 'Cluster view: no clusters yet (menu > Create clusters)'
                : 'Cluster view: ${ref.read(clusterPointsProvider).length} clusters')
            : 'Point view: ${ref.read(runPointsProvider).length} points';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<bool> _confirmReplaceClusters(Dataset existing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace clusters?'),
        content: Text(
          'This run already has ${existing.treeCount} clusters. They will be '
          'replaced by new, unvisited clusters and their visited marks are lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Makes a fresh cluster set (100 m grid) from the active run's points,
  /// like an import created on the spot. All clusters start unvisited.
  Future<void> _createClusters() async {
    final run = ref.read(activeRunProvider);
    if (run == null) return;
    final existing = ref.read(activeClusterSetProvider);
    if (existing != null && !await _confirmReplaceClusters(existing)) return;

    final points = await ref.read(datasetPointsProvider(run.id).future);
    final parks = (await ref.read(parksProvider.future)).parks;
    if (points.isEmpty) {
      _snack('This run has no points to cluster.');
      return;
    }
    final set = createClusterSet(run, points, parks: parks);
    await ref
        .read(datasetRepositoryProvider)
        .replaceClusterSet(run.id, set.dataset, set.clusters);
    refreshDatasets(ref, changedDatasetIds: [set.dataset.id]);
    _snack('Created ${set.clusters.length} clusters from ${points.length} points '
        '(${AppConfig.clusterCellMeters.round()} m grid).');
  }

  /// Imports a cluster CSV from storage as the active run's cluster set.
  Future<void> _importClusterCsv() async {
    final run = ref.read(activeRunProvider);
    if (run == null) return;
    final PickedFile? picked;
    try {
      picked = await pickPointsFile();
    } on FileImportException catch (e) {
      _snack(e.message);
      return;
    } catch (e) {
      _snack('Could not open the file: $e');
      return;
    }
    if (picked == null) return;

    final result = await compute(_parseClusterFile, (picked, run.id));
    if (!mounted) return;
    if (!result.success) {
      await _showReport('Cluster import failed', [result.error ?? 'Unknown error']);
      return;
    }
    final existing = ref.read(activeClusterSetProvider);
    if (existing != null && !await _confirmReplaceClusters(existing)) return;

    await ref
        .read(datasetRepositoryProvider)
        .replaceClusterSet(run.id, result.dataset!, result.trees!);
    refreshDatasets(ref, changedDatasetIds: [result.dataset!.id]);
    if (!mounted) return;
    await _showReport(
      'Imported ${result.trees!.length} clusters',
      result.report!.summaryLines(),
    );
  }

  /// Saves all clusters of the active run to a CSV on the device (Android
  /// "save" dialog). The file can be imported again in cluster view.
  Future<void> _saveClusters() async {
    final run = ref.read(activeRunProvider);
    final set = ref.read(activeClusterSetProvider);
    if (run == null || set == null) {
      _snack('This run has no clusters to save.');
      return;
    }
    try {
      final clusters = await ref.read(datasetPointsProvider(set.id).future);
      final saved = await saveCsvToDevice(
        fileName: clustersFileName(run.name),
        csv: buildVisitedCsv(runName: run.name, points: const [], clusters: clusters),
        dialogTitle: 'Save clusters CSV',
      );
      _snack(saved ? 'Saved ${clusters.length} clusters to device' : 'Save cancelled');
    } catch (e) {
      _snack('Saving failed: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReport(String title, List<String> lines) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(line),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final parksAsync = ref.watch(parksProvider);
    final park = ref.watch(selectedParkProvider);
    final locationState = ref.watch(locationControllerProvider);
    final navigation = ref.watch(navigationProvider);
    final parkTrees = ref.watch(parkTreesProvider);
    final basemap = ref.watch(basemapProvider);
    final settings = ref.watch(settingsProvider);
    final clusterView = settings.clusterView;
    final activeRun = ref.watch(activeRunProvider);
    final clusterSet = ref.watch(activeClusterSetProvider);
    // Keep both the run's points and its clusters loaded, so switching views
    // never waits for the database.
    ref.watch(runPointsProvider);
    ref.watch(clusterPointsProvider);

    ref.listen<bool>(
      navigationProvider.select((s) => s.isActive),
      (previous, active) {
        unawaited(ScreenWake.instance.setKeepOn(active));
        // Walking into the park starts navigation: follow the user.
        if (active && previous == false && !_follow) {
          final location = ref.read(locationControllerProvider).location;
          if (location != null) _startFollowing(location);
        }
      },
    );
    ref.listen<UserLocation?>(
      locationControllerProvider.select((s) => s.location),
      (_, location) => _onLocation(location),
    );
    final parkCounts = ref.watch(visibleParkCountsProvider);
    final hereMembership = locationState.location == null
        ? null
        : findParkMembership(
            parksAsync.valueOrNull?.parks ?? const <Park>[],
            locationState.location!.latitude,
            locationState.location!.longitude,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(park?.name ?? 'Park map'),
        actions: [
          IconButton(
            icon: Icon(clusterView ? Icons.bubble_chart : Icons.bubble_chart_outlined),
            tooltip: clusterView
                ? 'Cluster view - tap for individual points'
                : 'Point view - tap for clusters (${AppConfig.clusterCellMeters.round()} m)',
            onPressed: _toggleClusterView,
          ),
          if (clusterView)
            PopupMenuButton<String>(
              tooltip: 'Cluster menu',
              enabled: activeRun != null,
              onSelected: (value) {
                if (value == 'create') _createClusters();
                if (value == 'import') _importClusterCsv();
                if (value == 'save') _saveClusters();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'create',
                  child: Text(clusterSet == null
                      ? 'Create clusters'
                      : 'Re-create clusters'),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Import cluster CSV'),
                ),
                PopupMenuItem(
                  value: 'save',
                  enabled: clusterSet != null,
                  child: const Text('Save clusters to device (CSV)'),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Home',
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          _ParkSelector(
            parksAsync: parksAsync,
            selected: park,
            onSelected: _selectPark,
            counts: parkCounts,
            noun: clusterView ? 'clusters' : 'points',
          ),
          _RunBar(
            run: activeRun,
            clusterView: clusterView,
            clusterSet: clusterSet,
            countInPark: park == null ? null : (parkCounts[park.id] ?? 0),
          ),
          Expanded(
            child: park == null
                ? _NoParkPlaceholder(
                    parksAsync: parksAsync,
                    herePark: hereMembership?.park,
                    onOpen: _selectPark,
                  )
                : Stack(
                    children: [
                      _buildMap(
                        park: park,
                        location: locationState.location,
                        navigation: navigation,
                        parkTrees: parkTrees,
                        basemap: basemap.valueOrNull,
                        settings: settings,
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._buildBanners(locationState, basemap),
                            if (clusterView && activeRun != null && clusterSet == null)
                              StatusBanner(
                                icon: Icons.bubble_chart,
                                color: AppTheme.clusterColor,
                                message: 'This run has no clusters yet, so the '
                                    'map is empty. Create or import them from '
                                    'the ⋮ menu, or switch to point view.',
                                actionLabel: 'Point view',
                                onAction: _toggleClusterView,
                              ),
                            NavigationCard(
                              state: navigation,
                              parkName: park.name,
                              areaLabel: navigation.areaIndex == null
                                  ? ''
                                  : park.areaLabel(navigation.areaIndex!),
                              useFeet: settings.useFeet,
                              onMarkVisited: (tree) => _setVisited(tree, true),
                              onOpenPoint: _openPoint,
                              clusterView: clusterView,
                              noPointsMessage: activeRun == null
                                  ? 'No run imported. Import a CSV on Home.'
                                  : clusterView && clusterSet == null
                                      ? 'No clusters for this run yet. Use the '
                                          'cluster menu (⋮) to create or import them.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: park == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fit_park',
                  tooltip: 'Show whole park',
                  onPressed: () {
                    setState(() => _follow = false);
                    _fitToPark(park, location: locationState.location);
                  },
                  child: const Icon(Icons.zoom_out_map),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'follow',
                  tooltip: _follow ? 'Stop following' : 'Follow my position',
                  onPressed: _toggleFollow,
                  child: Icon(_follow ? Icons.my_location : Icons.location_searching),
                ),
              ],
            ),
    );
  }

  Widget _buildMap({
    required Park park,
    required UserLocation? location,
    required NavigationState navigation,
    required ParkTrees parkTrees,
    required Basemap? basemap,
    required AppSettings settings,
  }) {
    final target = navigation.isActive ? navigation.target : null;
    final route = navigation.isActive ? navigation.routeAfterUser : const <LatLng>[];
    final glide = Duration(
      milliseconds: (settings.gpsIntervalSeconds * 1000).clamp(300, 1000),
    );

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: _cameraFit(_boundsFor(park, location)),
        minZoom: MapConfig.minZoom,
        maxZoom: MapConfig.maxZoom,
        backgroundColor: MapConfig.backgroundColor,
        interactionOptions: const InteractionOptions(
          // North-up map: arrows and bearings stay meaningful.
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _mapReady = true;
          final current = ref.read(locationControllerProvider).location;
          if (_follow && current != null) {
            _mapController.move(
              current.position,
              math.max(_mapController.camera.zoom, MapConfig.followZoom),
            );
          }
        },
        onMapEvent: (event) {
          // Dragging the map stops following; pinch-zoom keeps it.
          if (_follow &&
              (event.source == MapEventSource.dragStart ||
                  event.source == MapEventSource.onDrag)) {
            setState(() => _follow = false);
          }
        },
      ),
      children: [
        if (basemap != null && basemap.isReady)
          VectorTileLayer(
            tileProviders: basemap.tileProviders!,
            theme: basemap.theme!,
            layerMode: VectorTileLayerMode.raster,
            maximumZoom: MapConfig.maxZoom,
          ),
        PolygonLayer(
          polygons: [
            for (final area in park.areas)
              Polygon(
                points: area.outer,
                holePointsList: area.holes.isEmpty ? null : area.holes,
                color: AppTheme.parkBorderColor.withValues(alpha: 0.06),
                borderColor: AppTheme.parkBorderColor,
                borderStrokeWidth: 2.5,
              ),
          ],
        ),
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                color: AppTheme.routeColor.withValues(alpha: 0.6),
                strokeWidth: 3,
                pattern: StrokePattern.dashed(segments: const [12, 8]),
              ),
            ],
          ),
        MarkerLayer(markers: _pointMarkers(parkTrees, target)),
        UserLocationLayer(
          location: location,
          target: target?.position,
          duration: glide,
          onAnimatedMove: _onAnimatedMove,
        ),
        const SimpleAttributionWidget(
          source: Text(MapConfig.attribution),
          alignment: Alignment.bottomLeft,
        ),
      ],
    );
  }

  List<Marker> _pointMarkers(ParkTrees parkTrees, Tree? target) {
    final entries = <(Tree, PointMarkerKind)>[
      for (final tree in parkTrees.all)
        (
          tree,
          !parkTrees.isInPark(tree)
              ? PointMarkerKind.outside
              : tree.visited
                  ? PointMarkerKind.visited
                  : tree.id == target?.id
                      ? PointMarkerKind.target
                      : PointMarkerKind.pending,
        ),
    ]..sort((a, b) => a.$2.paintOrder.compareTo(b.$2.paintOrder));

    return [
      for (final (tree, kind) in entries)
        Marker(
          key: ValueKey(tree.id),
          point: tree.position,
          width: markerSize(kind, clusterCount: tree.memberCount),
          height: markerSize(kind, clusterCount: tree.memberCount),
          child: PointMarker(
            kind: kind,
            clusterCount: tree.memberCount,
            onTap: () => _openPoint(tree),
          ),
        ),
    ];
  }

  List<Widget> _buildBanners(
    LocationState locationState,
    AsyncValue<Basemap> basemap,
  ) {
    final controller = ref.read(locationControllerProvider.notifier);
    final banners = <Widget>[];
    switch (locationState.status) {
      case LocationStatus.serviceDisabled:
        banners.add(StatusBanner(
          icon: Icons.location_disabled,
          message: 'Location is turned off.',
          actionLabel: 'Turn on',
          onAction: controller.openLocationSettings,
        ));
      case LocationStatus.permissionDenied:
        banners.add(StatusBanner(
          icon: Icons.location_off,
          message: 'Location permission is needed for navigation.',
          actionLabel: 'Allow',
          onAction: controller.restart,
        ));
      case LocationStatus.permissionDeniedForever:
        banners.add(StatusBanner(
          icon: Icons.location_off,
          message: 'Location permission was denied. Enable it in app settings.',
          actionLabel: 'Settings',
          onAction: controller.openAppSettings,
        ));
      case LocationStatus.unavailable:
        banners.add(StatusBanner(
          icon: Icons.error_outline,
          message: 'GPS unavailable: ${locationState.message ?? 'unknown error'}',
          actionLabel: 'Retry',
          onAction: controller.restart,
        ));
      case LocationStatus.starting:
      case LocationStatus.ready:
        break;
    }
    if (locationState.status == LocationStatus.ready && locationState.approximate) {
      banners.add(StatusBanner(
        icon: Icons.gps_off,
        message: 'Only approximate location is allowed; positions can be '
            'off by kilometres. Allow "precise" location.',
        actionLabel: 'Settings',
        onAction: controller.openAppSettings,
      ));
    }
    final map = basemap.valueOrNull;
    if (map != null && !map.isReady) {
      banners.add(StatusBanner(
        icon: Icons.map_outlined,
        message: map.message ?? 'Offline map unavailable.',
      ));
    }
    return banners;
  }
}

/// Which run (CSV) and view the map is showing.
class _RunBar extends StatelessWidget {
  const _RunBar({
    required this.run,
    required this.clusterView,
    required this.clusterSet,
    required this.countInPark,
  });

  final Dataset? run;
  final bool clusterView;
  final Dataset? clusterSet;

  /// Visible points (or clusters) inside the selected park; null when no
  /// park is selected.
  final int? countInPark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = run;
    final inPark = countInPark;
    final where = inPark == null ? '' : ' ($inPark in this park)';
    final String text;
    if (current == null) {
      text = 'No run imported';
    } else if (clusterView) {
      final set = clusterSet;
      text = set == null
          ? 'Run: ${current.name} · clusters: none yet'
          : 'Run: ${current.name} · ${set.treeCount} clusters$where';
    } else {
      text = 'Run: ${current.name} · ${current.treeCount} points$where';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            clusterView ? Icons.bubble_chart : Icons.place_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkSelector extends StatelessWidget {
  const _ParkSelector({
    required this.parksAsync,
    required this.selected,
    required this.onSelected,
    required this.counts,
    required this.noun,
  });

  final AsyncValue<ParkLoadResult> parksAsync;
  final Park? selected;
  final ValueChanged<Park> onSelected;

  /// Visible points (or clusters) of the active run per park id.
  final Map<String, int> counts;

  /// "points" or "clusters".
  final String noun;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: parksAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Could not load parks: $e'),
        data: (result) {
          return Row(
            children: [
              Expanded(
                child: result.parks.isEmpty
                    ? const Text('No parks bundled (add GeoJSON files to parks/)')
                    : DropdownButton<String>(
                        isExpanded: true,
                        value: selected?.id,
                        hint: const Text('Select a park'),
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final park in result.parks)
                            DropdownMenuItem(
                              value: park.id,
                              child: Text(
                                [
                                  park.name,
                                  if (park.areas.length > 1)
                                    '${park.areas.length} areas',
                                  if ((counts[park.id] ?? 0) > 0)
                                    '${counts[park.id]} $noun',
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) {
                          for (final park in result.parks) {
                            if (park.id == id) onSelected(park);
                          }
                        },
                      ),
              ),
              if (result.errors.isNotEmpty)
                IconButton(
                  tooltip: 'Park files with errors',
                  icon: Icon(Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Park files that could not be loaded'),
                      content: SingleChildScrollView(
                        child: Text(result.errors.join('\n\n')),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NoParkPlaceholder extends StatelessWidget {
  const _NoParkPlaceholder({
    required this.parksAsync,
    required this.herePark,
    required this.onOpen,
  });

  final AsyncValue<ParkLoadResult> parksAsync;

  /// Park the user is standing in (by GPS), if any.
  final Park? herePark;
  final ValueChanged<Park> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasParks = parksAsync.valueOrNull?.parks.isNotEmpty ?? false;
    final here = herePark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No park selected',
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              hasParks
                  ? 'Choose a park above. The list shows how many points of '
                      'the active run each park has.'
                  : 'Add park boundaries to parks/*.geojson, run '
                      'tools/build_map.py and rebuild the app.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (here != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => onOpen(here),
                icon: const Icon(Icons.my_location),
                label: Text('You are in ${here.name} - open it'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
