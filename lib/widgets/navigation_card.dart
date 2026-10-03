import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/tree.dart';
import '../providers/navigation_provider.dart';
import '../utils/bearing_calculator.dart';
import '../utils/distance_calculator.dart';

/// Top card on the map: where to walk next, or why navigation is idle.
class NavigationCard extends StatelessWidget {
  const NavigationCard({
    super.key,
    required this.state,
    required this.parkName,
    required this.areaLabel,
    required this.useFeet,
    required this.onMarkVisited,
    required this.onOpenPoint,
  });

  final NavigationState state;
  final String parkName;

  /// e.g. "area 2 of 3"; empty for single-area parks.
  final String areaLabel;
  final bool useFeet;
  final ValueChanged<Tree> onMarkVisited;
  final ValueChanged<Tree> onOpenPoint;

  @override
  Widget build(BuildContext context) {
    final where = areaLabel.isEmpty ? parkName : '$parkName ($areaLabel)';
    switch (state.phase) {
      case NavigationPhase.noPark:
        return const SizedBox.shrink();
      case NavigationPhase.waitingForLocation:
        return const _InfoCard(
          icon: Icons.gps_not_fixed,
          text: 'Waiting for a GPS fix...',
        );
      case NavigationPhase.outsidePark:
        return _InfoCard(
          icon: Icons.info_outline,
          text: 'You are outside $parkName. Navigation starts when you are '
              'inside the park boundary. Points outside the park are shown '
              'in grey but are not navigated.',
        );
      case NavigationPhase.noPoints:
        return _InfoCard(
          icon: Icons.info_outline,
          text: 'No imported points in $where. Import a CSV or enable a dataset.',
        );
      case NavigationPhase.allVisited:
        return _InfoCard(
          icon: Icons.task_alt,
          color: AppTheme.visitedColor,
          text: 'All ${state.totalInArea} points in $where are visited.',
        );
      case NavigationPhase.navigating:
        return _buildNavigating(context);
    }
  }

  Widget _buildNavigating(BuildContext context) {
    final target = state.target!;
    final distance = state.targetDistance ?? 0;
    final bearing = state.targetBearing ?? 0;
    final arrived = state.arrived;
    final theme = Theme.of(context);
    final accent = arrived ? AppTheme.visitedColor : AppTheme.targetColor;

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: arrived
                      ? Icon(Icons.where_to_vote, color: accent, size: 40)
                      : Transform.rotate(
                          // The map is always north-up, so the absolute
                          // bearing points the right way on screen.
                          angle: bearing * math.pi / 180,
                          child: Icon(Icons.navigation, color: accent, size: 40),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arrived ? 'You have arrived' : 'Next point',
                        style: theme.textTheme.labelMedium?.copyWith(color: accent),
                      ),
                      Text(
                        target.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${formatDistance(distance, useFeet: useFeet)}  ·  '
                        '${formatBearing(bearing)}',
                        style: theme.textTheme.titleLarge?.copyWith(color: accent),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Point details',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => onOpenPoint(target),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (arrived)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.visitedColor,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => onMarkVisited(target),
                icon: const Icon(Icons.check_circle),
                label: const Text('Mark visited'),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onMarkVisited(target),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark visited'),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '${state.visitedInArea} of ${state.totalInArea} visited'
              '${areaLabel.isEmpty ? '' : ' in $areaLabel'}  ·  '
              '${state.upcoming.length} more after this  ·  '
              'route ${formatDistance(state.remainingDistance, useFeet: useFeet)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
