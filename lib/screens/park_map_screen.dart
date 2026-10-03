import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../config/map_config.dart';
import '../config/theme.dart';
import '../models/app_settings.dart';
import '../models/park.dart';
import '../models/tree.dart';
import '../models/user_location.dart';
import '../providers/basemap_provider.dart';
import '../providers/location_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/park_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tree_repository_provider.dart';
import '../providers/trees_provider.dart';
import '../services/basemap_service.dart';
import '../services/park_service.dart';
import '../services/screen_wake_service.dart';
import '../widgets/navigation_card.dart';
import '../widgets/safety_prompt.dart';
import '../widgets/status_banner.dart';
import '../widgets/tree_marker_widget.dart';
import '../widgets/user_location_layer.dart';
import 'tree_detail_screen.dart';

/// Navigation page. The safety reminder is shown first; the map, GPS and
/// navigation only start after the user taps "Okay". Closing the reminder
/// with the back button leaves the page.
class ParkMapScreen extends StatefulWidget {
  const ParkMapScreen({super.key});

  @override
  State<ParkMapScreen> createState() => _ParkMapScreenState();
}

class _ParkMapScreenState extends State<ParkMapScreen> {
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

  /// The user picked a park by hand: no automatic park switching.
  bool _userChosePark = false;

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
    if (park == null) {
      _autoSelectPark(location);
      return;
    }
    if (!_followDecided) {
      _followDecided = true;
      if (park.containsPoint(location.latitude, location.longitude)) {
        _startFollowing(location);
      }
    }
  }

  /// Opens the park the user is standing in, unless a park was chosen by hand.
  void _autoSelectPark(UserLocation? location) {
    if (location == null || _userChosePark) return;
    if (ref.read(selectedParkProvider) != null) return;
    final parks = ref.read(parksProvider).valueOrNull?.parks ?? const <Park>[];
    final membership =
        findParkMembership(parks, location.latitude, location.longitude);
    if (membership == null) return;
    // Change provider state outside of the current notification.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(selectedParkIdProvider.notifier).state = membership.park.id;
      _followDecided = true;
      _startFollowing(location);
    });
  }

  void _selectPark(Park park) {
    _userChosePark = true;
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
    ref.invalidate(enabledTreesProvider);
    ref.invalidate(treeByIdProvider(tree.id));
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
    ref.listen<AsyncValue<ParkLoadResult>>(
      parksProvider,
      (_, _) => _autoSelectPark(ref.read(locationControllerProvider).location),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(park?.name ?? 'Park map'),
        actions: [
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
          ),
          Expanded(
            child: park == null
                ? _NoParkPlaceholder(parksAsync: parksAsync)
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
                            NavigationCard(
                              state: navigation,
                              parkName: park.name,
                              areaLabel: navigation.areaIndex == null
                                  ? ''
                                  : park.areaLabel(navigation.areaIndex!),
                              useFeet: settings.useFeet,
                              onMarkVisited: (tree) => _setVisited(tree, true),
                              onOpenPoint: _openPoint,
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
          width: kind.size,
          height: kind.size,
          child: PointMarker(kind: kind, onTap: () => _openPoint(tree)),
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

class _ParkSelector extends StatelessWidget {
  const _ParkSelector({
    required this.parksAsync,
    required this.selected,
    required this.onSelected,
  });

  final AsyncValue<ParkLoadResult> parksAsync;
  final Park? selected;
  final ValueChanged<Park> onSelected;

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
                                park.areas.length > 1
                                    ? '${park.name} (${park.areas.length} areas)'
                                    : park.name,
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
  const _NoParkPlaceholder({required this.parksAsync});

  final AsyncValue<ParkLoadResult> parksAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasParks = parksAsync.valueOrNull?.parks.isNotEmpty ?? false;
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
                  ? 'Choose a park above. When you are inside a park it opens '
                      'automatically once GPS has a fix.'
                  : 'Add park boundaries to parks/*.geojson, run '
                      'tools/build_map.py and rebuild the app.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
