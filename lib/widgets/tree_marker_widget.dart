import 'package:flutter/material.dart';

import '../config/theme.dart';

/// How a point or cluster is drawn. Colours never depend on classification.
enum PointMarkerKind {
  /// Unvisited, inside the selected park.
  pending,

  /// The point or cluster you are being navigated to.
  target,

  /// Marked visited.
  visited,

  /// Outside the selected park: shown, never navigated.
  outside,
}

extension PointMarkerKindSize on PointMarkerKind {
  /// Size of a point marker on the map.
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

/// Marker size: fixed per kind for points; for clusters it grows with the
/// number of trees (28 px + 6 px per extra tree, max 56 px, +6 px for the
/// target), like the old app.
double markerSize(PointMarkerKind kind, {int? clusterCount}) {
  if (clusterCount == null) return kind.size;
  final base = (28.0 + (clusterCount - 1) * 6.0).clamp(28.0, 56.0);
  return base + (kind == PointMarkerKind.target ? 6.0 : 0.0);
}

/// A point (icon) or a cluster (number of trees) on the map.
class PointMarker extends StatelessWidget {
  const PointMarker({
    super.key,
    required this.kind,
    this.clusterCount,
    this.onTap,
  });

  final PointMarkerKind kind;

  /// Set for clusters: number of trees (0 = unknown, shown as "?").
  final int? clusterCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final count = clusterCount;
    final isCluster = count != null;
    final (Color color, IconData? icon, double iconSize, double border) =
        switch (kind) {
      PointMarkerKind.target => (AppTheme.targetColor, Icons.flag, 24.0, 4.0),
      PointMarkerKind.pending => (
          isCluster ? AppTheme.clusterColor : AppTheme.pointColor,
          Icons.place,
          16.0,
          2.0,
        ),
      PointMarkerKind.visited => (AppTheme.visitedColor, Icons.check, 16.0, 2.0),
      PointMarkerKind.outside => (AppTheme.outsideColor, null, 0.0, 2.0),
    };
    final size = markerSize(kind, clusterCount: count);

    final Widget? content;
    if (count != null) {
      content = Text(
        count > 0 ? '$count' : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      );
    } else if (icon != null) {
      content = Icon(icon, color: Colors.white, size: iconSize);
    } else {
      content = null;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: size - 4,
          height: size - 4,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isCluster ? 0.92 : 1),
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
          child: content,
        ),
      ),
    );
  }
}
