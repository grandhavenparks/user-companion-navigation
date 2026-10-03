import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/tree.dart';
import '../models/user_location.dart';
import '../config/tile_zoom_limits.dart';
import '../providers/location_provider.dart';
import '../providers/park_provider.dart';
import '../providers/tile_zoom_limits_provider.dart';
import '../services/park_route_service.dart';
import '../utils/distance_calculator.dart';
import '../widgets/map_layer_selector.dart';
import '../widgets/tree_marker_widget.dart';
import 'tree_detail_screen.dart';

class ParkMapScreen extends ConsumerStatefulWidget {
  const ParkMapScreen({super.key});

  @override
  ConsumerState<ParkMapScreen> createState() => _ParkMapScreenState();
}

class _ParkMapScreenState extends ConsumerState<ParkMapScreen> {
  final MapController _mapController = MapController();
  LatLng? _lastCenter;
  double _currentZoom = AppConfig.defaultMapZoom;
  MapLayerType _layerType = MapLayerType.osm; // Changed to OSM (more reliable)

  @override
  Widget build(BuildContext context) {
    final parksAsync = ref.watch(parksProvider);
    final selectedPark = ref.watch(selectedParkProvider);
    final locationAsync = ref.watch(locationStreamProvider);
    final parkTrees = ref.watch(parkTreesProvider);
    final parkRoute = ref.watch(parkRouteProvider);
    final nextTree = ref.watch(nextTreeProvider);
    
    final parkPoints = selectedPark != null
        ? ref.watch(parkPointsProvider(selectedPark.id))
        : <LatLng>[];
    final tileZoomLimits = ref.watch(tileZoomLimitsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Park Navigation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Go to home',
            onPressed: () => Navigator.of(
              context,
            ).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: Column(
        children: [
          // Park selector dropdown
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: parksAsync.when(
              data: (parks) {
                if (parks.isEmpty) {
                  return const Text('No parks available');
                }
                return DropdownButton<String>(
                  isExpanded: true,
                  value: selectedPark?.id,
                  hint: const Text('Select a park'),
                  items: parks.map((park) {
                    return DropdownMenuItem(
                      value: park.id,
                      child: Text(park.name),
                    );
                  }).toList(),
                  onChanged: (parkId) {
                    if (parkId != null) {
                      final park = parks.firstWhere((p) => p.id == parkId);
                      ref.read(selectedParkProvider.notifier).state = park;
                      _focusOnPark(park);
                    }
                  },
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error loading parks: $e'),
            ),
          ),
          // Map view (only after a park is selected)
          Expanded(
            child: parksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading parks: $e')),
              data: (parks) {
                if (parks.isEmpty) {
                  return const Center(child: Text('No parks available'));
                }
                if (selectedPark == null) {
                  return _noParkSelectedPlaceholder(context);
                }
                return locationAsync.when(
                  data: (userLoc) {
                    return _buildMap(
                      context,
                      tileZoomLimits: tileZoomLimits,
                      userLocation: userLoc,
                      parkTrees: parkTrees,
                      parkRoute: parkRoute,
                      nextTree: nextTree,
                      parkPoints: parkPoints,
                    );
                  },
                  loading: () => _buildMap(
                    context,
                    tileZoomLimits: tileZoomLimits,
                    userLocation: null,
                    parkTrees: parkTrees,
                    parkRoute: parkRoute,
                    nextTree: nextTree,
                    parkPoints: parkPoints,
                  ),
                  error: (e, _) => Center(child: Text('Location error: $e')),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: selectedPark == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'layer',
                  onPressed: () => _showLayerSelector(context, tileZoomLimits),
                  child: const Icon(Icons.layers),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'focus_park',
                  onPressed: () => _focusOnPark(selectedPark),
                  child: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
    );
  }

  Widget _noParkSelectedPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No park selected',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a park above to show the map.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(
    BuildContext context, {
    required TileZoomLimits tileZoomLimits,
    required UserLocation? userLocation,
    required List<Tree> parkTrees,
    required ParkRoute? parkRoute,
    required Tree? nextTree,
    required List<LatLng> parkPoints,
  }) {
    final selectedPark = ref.watch(selectedParkProvider);
    
    // Check if user is inside the park boundary
    final isUserInPark = selectedPark != null && 
        userLocation != null && 
        selectedPark.containsPoint(userLocation.latitude, userLocation.longitude);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _lastCenter ?? selectedPark!.center,
            initialZoom: _currentZoom,
            minZoom: tileZoomLimits.minZoomForMap,
            maxZoom: maxZoomForLayerType(_layerType, tileZoomLimits),
            onPositionChanged: (position, hasGesture) {
              _lastCenter = position.center;
              if (position.zoom != null) {
                _currentZoom = position.zoom!;
              }
            },
          ),
          children: [
            tileLayerForType(_layerType, tileZoomLimits),
            // Draw park boundary
            if (selectedPark != null) _buildParkBoundaryLayer(selectedPark),
            // Draw park points as polygon boundary
            if (parkPoints.isNotEmpty) _buildPointsPolygonLayer(parkPoints),
            // Draw closed-loop route - only if user is inside the park
            if (parkRoute != null && isUserInPark) _buildRouteLayer(parkRoute),
            // Draw user location with animated marker
            if (userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      userLocation.latitude,
                      userLocation.longitude,
                    ),
                    width: 60,
                    height: 60,
                    child: _AnimatedUserMarker(
                      isNavigating: isUserInPark && nextTree != null,
                      heading: userLocation.heading ?? -1.0, // -1 means no heading
                    ),
                  ),
                ],
              ),
            // Draw point markers (from CSV) as tree locations
            if (parkPoints.isNotEmpty) _buildPointMarkersLayer(parkPoints),
            // Draw tree markers (from imported GeoJSON)
            if (parkTrees.isNotEmpty)
              MarkerLayer(
                markers: parkTrees.map((tree) {
                  final isNext = nextTree?.id == tree.id;
                  return Marker(
                    point: LatLng(tree.latitude, tree.longitude),
                    width: isNext ? 50 : 40,
                    height: isNext ? 50 : 40,
                    child: GestureDetector(
                      onTap: () => _onTreeTap(tree),
                      child: TreeMarkerWidget(
                        tree: tree,
                        isHighlighted: isNext,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
        // Navigation info card - only show if user is in the park
        if (nextTree != null && userLocation != null && selectedPark != null && isUserInPark)
          Positioned(
            left: 16,
            top: 16,
            right: 16,
            child: _NavigationCard(
              nextTree: nextTree,
              userLocation: userLocation,
              parkRoute: parkRoute,
            ),
          ),
        // Route statistics - only show if user is in the park
        if (parkRoute != null && selectedPark != null && isUserInPark)
          Positioned(
            left: 16,
            bottom: 16,
            child: _RouteStatsCard(route: parkRoute),
          ),
        // Navigation active indicator
        if (isUserInPark && nextTree != null)
          Positioned(
            right: 16,
            top: 16,
            child: Card(
              elevation: 4,
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Navigation Active',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  PolygonLayer _buildParkBoundaryLayer(park) {
    return PolygonLayer(
      polygons: [
        Polygon(
          points: park.boundary,
          color: Colors.green.withOpacity(0.1),
          borderColor: Colors.green,
          borderStrokeWidth: 3.0,
          isFilled: true,
        ),
      ],
    );
  }

  PolylineLayer _buildRouteLayer(ParkRoute route) {
    return PolylineLayer(
      polylines: [
        Polyline(
          points: route.pathPoints,
          color: Colors.purple.withOpacity(0.7),
          strokeWidth: 4.0,
          borderColor: Colors.white,
          borderStrokeWidth: 1.0,
        ),
      ],
    );
  }
  
  /// Build polygon layer for park points (closed boundary covering all points)
  PolygonLayer _buildPointsPolygonLayer(List<LatLng> points) {
    return PolygonLayer(
      polygons: [
        Polygon(
          points: points,
          color: Colors.orange.withOpacity(0.15),
          borderColor: Colors.orange.withOpacity(0.8),
          borderStrokeWidth: 2.0,
          isFilled: true,
          isDotted: true,
        ),
      ],
    );
  }
  
  /// Build marker layer for park points (showing actual point locations)
  MarkerLayer _buildPointMarkersLayer(List<LatLng> points) {
    return MarkerLayer(
      markers: points.map((point) {
        return Marker(
          point: point,
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.location_on,
              color: Colors.white,
              size: 14,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _onTreeTap(Tree tree) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TreeDetailScreen(treeId: tree.id),
      ),
    );
  }

  /// Fits the camera to [park] bounds. Must run after [FlutterMap] has mounted
  /// and wired [MapController]; otherwise [fitCamera] throws (e.g. first park selection).
  void _focusOnPark(park) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = park.bounds;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            bounds.southwest,
            bounds.northeast,
          ),
          padding: const EdgeInsets.all(50),
        ),
      );
    });
  }

  void _showLayerSelector(BuildContext context, TileZoomLimits limits) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Map Layer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('OpenStreetMap'),
              leading: Radio<MapLayerType>(
                value: MapLayerType.osm,
                groupValue: _layerType,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _layerType = value;
                      final cap = maxZoomForLayerType(value, limits);
                      if (_currentZoom > cap) {
                        _currentZoom = cap;
                        if (_lastCenter != null) {
                          _mapController.move(_lastCenter!, _currentZoom);
                        }
                      }
                    });
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Topographic'),
              leading: Radio<MapLayerType>(
                value: MapLayerType.topo,
                groupValue: _layerType,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _layerType = value;
                      final cap = maxZoomForLayerType(value, limits);
                      if (_currentZoom > cap) {
                        _currentZoom = cap;
                        if (_lastCenter != null) {
                          _mapController.move(_lastCenter!, _currentZoom);
                        }
                      }
                    });
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationCard extends ConsumerWidget {
  const _NavigationCard({
    required this.nextTree,
    required this.userLocation,
    required this.parkRoute,
  });

  final Tree nextTree;
  final UserLocation userLocation;
  final ParkRoute? parkRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distance = calculateDistance(
      userLocation.latitude,
      userLocation.longitude,
      nextTree.latitude,
      nextTree.longitude,
    );

    final bearing = ParkRouteService.calculateBearing(
      fromLat: userLocation.latitude,
      fromLng: userLocation.longitude,
      toLat: nextTree.latitude,
      toLng: nextTree.longitude,
    );

    final pathDistance = parkRoute?.getDistanceToTree(nextTree) ?? distance;

    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.navigation, color: Colors.purple, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Next Tree',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Text(
                        nextTree.filename,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      formatDistance(distance),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const Text('Direct', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      formatDistance(pathDistance),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const Text('On Path', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      _getDirectionText(bearing),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const Text('Direction', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getDirectionText(double bearing) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}

class _RouteStatsCard extends StatelessWidget {
  const _RouteStatsCard({required this.route});

  final ParkRoute route;

  @override
  Widget build(BuildContext context) {
    final visited = route.trees.where((t) => t.visited).length;
    final total = route.trees.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Route Progress',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('$visited of $total trees visited'),
            Text('Loop: ${formatDistance(route.totalDistance)}'),
          ],
        ),
      ),
    );
  }
}

/// Animated user location marker with pulsing effect and heading indicator
class _AnimatedUserMarker extends StatefulWidget {
  const _AnimatedUserMarker({
    required this.isNavigating,
    required this.heading,
  });

  final bool isNavigating;
  final double heading;

  @override
  State<_AnimatedUserMarker> createState() => _AnimatedUserMarkerState();
}

class _AnimatedUserMarkerState extends State<_AnimatedUserMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing outer circle (only when navigating)
            if (widget.isNavigating)
              Container(
                width: 60 * _animation.value,
                height: 60 * _animation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(0.3 / _animation.value),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.5 / _animation.value),
                    width: 2,
                  ),
                ),
              ),
            // Accuracy circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isNavigating 
                    ? Colors.green.withOpacity(0.3)
                    : Colors.blue.withOpacity(0.3),
                border: Border.all(
                  color: widget.isNavigating ? Colors.green : Colors.blue,
                  width: 3,
                ),
              ),
            ),
            // Direction arrow (if heading available and navigating)
            if (widget.isNavigating && widget.heading >= 0)
              Transform.rotate(
                angle: widget.heading * (3.14159265359 / 180.0),
                child: Icon(
                  Icons.navigation,
                  color: widget.isNavigating ? Colors.green : Colors.blue,
                  size: 24,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.white),
                  ],
                ),
              )
            else
              // User icon when not navigating or no heading
              Icon(
                Icons.person,
                color: widget.isNavigating ? Colors.green : Colors.blue,
                size: 20,
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.white),
                ],
              ),
          ],
        );
      },
    );
  }
}

