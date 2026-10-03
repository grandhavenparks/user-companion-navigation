import 'package:flutter/material.dart';

import '../config/theme.dart';

/// How a point is drawn. Points are not coloured by health classification.
enum PointMarkerKind {
  /// Unvisited point inside the selected park.
  pending,

  /// The point you are being navigated to.
  target,

  /// Marked visited.
  visited,

  /// Outside the selected park: shown, never navigated.
  outside,
}

extension PointMarkerKindSize on PointMarkerKind {
  /// Size of the marker box on the map.
  double get size => switch (this) {
        PointMarkerKind.target => 46,
        PointMarkerKind.pending => 30,
        PointMarkerKind.visited => 28,
        PointMarkerKind.outside => 22,
      };

  /// Drawing order: higher values are painted on top.
  int get paintOrder => switch (this) {
        PointMarkerKind.outside => 0,
        PointMarkerKind.visited => 1,
        PointMarkerKind.pending => 2,
        PointMarkerKind.target => 3,
      };
}

class PointMarker extends StatelessWidget {
  const PointMarker({super.key, required this.kind, this.onTap});

  final PointMarkerKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon, iconSize, border) = switch (kind) {
      PointMarkerKind.target => (AppTheme.targetColor, Icons.flag, 24.0, 4.0),
      PointMarkerKind.pending => (AppTheme.pointColor, Icons.place, 16.0, 2.0),
      PointMarkerKind.visited => (AppTheme.visitedColor, Icons.check, 16.0, 2.0),
      PointMarkerKind.outside => (AppTheme.outsideColor, null, 0.0, 2.0),
    };
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: kind.size - 4,
          height: kind.size - 4,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: kind == PointMarkerKind.target
                  ? const Color(0xFFFFEB3B)
                  : Colors.white,
              width: border,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: icon == null
              ? null
              : Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}
