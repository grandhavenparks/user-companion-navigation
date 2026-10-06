import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/user_location.dart';
import '../utils/distance_calculator.dart';

/// Draws the user's position, GPS accuracy circle and the leg to the current
/// target. The marker glides between GPS fixes instead of jumping, and
/// [onAnimatedMove] lets the map follow the animated position smoothly.
///
/// Must be a child of a `FlutterMap`.
class UserLocationLayer extends StatefulWidget {
  const UserLocationLayer({
    super.key,
    required this.location,
    this.target,
    this.onAnimatedMove,
    this.duration = const Duration(milliseconds: 1000),
  });

  final UserLocation? location;

  /// When set, a solid line is drawn from the user to this point.
  final LatLng? target;
  final ValueChanged<LatLng>? onAnimatedMove;
  final Duration duration;

  @override
  State<UserLocationLayer> createState() => _UserLocationLayerState();
}

class _UserLocationLayerState extends State<UserLocationLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  LatLng? _from;
  LatLng? _to;
  LatLng? _current;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_onTick);
    final location = widget.location;
    if (location != null) {
      _from = _to = _current = location.position;
    }
  }

  @override
  void didUpdateWidget(covariant UserLocationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    final location = widget.location;
    if (location == null) return;
    final next = location.position;
    final to = _to;
    if (to != null && to.latitude == next.latitude && to.longitude == next.longitude) {
      return;
    }

    final from = _current;
    final jump = from == null
        ? double.infinity
        : calculateDistance(
            from.latitude, from.longitude, next.latitude, next.longitude);
    if (jump > AppConfig.snapDistanceMeters) {
      // First fix or a big jump (e.g. after the screen was off): no glide.
      _controller.stop();
      _from = _to = _current = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onAnimatedMove?.call(next);
      });
      return;
    }

    _from = from;
    _to = next;
    // Start after this frame: moving the map camera during a build is not
    // allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward(from: 0);
    });
  }

  void _onTick() {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;
    final t = _controller.value;
    final next = LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
    setState(() => _current = next);
    widget.onAnimatedMove?.call(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final location = widget.location;
    if (current == null || location == null) return const SizedBox.shrink();

    final accuracy = location.accuracy;
    final target = widget.target;
    return Stack(
      children: [
        if (accuracy != null && accuracy > 0)
          CircleLayer(
            circles: [
              CircleMarker(
                point: current,
                radius: accuracy,
                useRadiusInMeter: true,
                color: AppTheme.userColor.withValues(alpha: 0.12),
                borderColor: AppTheme.userColor.withValues(alpha: 0.5),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        if (target != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [current, target],
                color: AppTheme.routeColor,
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: current,
              width: 44,
              height: 44,
              child: _UserDot(heading: location.heading),
            ),
          ],
        ),
      ],
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot({this.heading});

  /// Degrees from north, null when not moving.
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: AppTheme.userColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
    final h = heading;
    if (h == null) return Center(child: dot);
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: h * math.pi / 180,
          child: const Icon(Icons.navigation, color: AppTheme.userColor, size: 40),
        ),
        dot,
      ],
    );
  }
}
