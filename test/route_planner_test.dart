import 'dart:math';

import 'package:user_navigation_companion/services/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chooseTarget', () {
    const a = PlanPoint('A', 43.0500, -86.2350);
    const b = PlanPoint('B', 43.0500, -86.2340);

    test('picks the nearest point when there is no target yet', () {
      final t = chooseTarget(latitude: 43.05, longitude: -86.2342, candidates: [a, b]);
      expect(t!.id, 'B');
    });

    test('keeps the current target when another is only slightly closer', () {
      final t = chooseTarget(
          latitude: 43.05, longitude: -86.2346, candidates: [a, b], currentTargetId: 'A');
      expect(t!.id, 'A');
      final t2 = chooseTarget(
          latitude: 43.05, longitude: -86.23448, candidates: [a, b], currentTargetId: 'A');
      expect(t2!.id, 'A', reason: 'B is closer but not by the switch margin');
    });

    test('switches when the user wandered clearly closer to another point', () {
      final t = chooseTarget(
          latitude: 43.05, longitude: -86.2342, candidates: [a, b], currentTargetId: 'A');
      expect(t!.id, 'B');
    });

    test('falls back to nearest when the target is gone (visited)', () {
      final t = chooseTarget(
          latitude: 43.05, longitude: -86.2346, candidates: [b], currentTargetId: 'A');
      expect(t!.id, 'B');
    });
  });

  group('orderOpenRoute', () {
    test('returns every point once and is never longer than nearest-neighbour', () {
      final random = Random(7);
      const start = PlanPoint('start', 43.05, -86.235);
      for (final n in [2, 5, 20, 80]) {
        final points = [
          for (var i = 0; i < n; i++)
            PlanPoint('p$i', 43.047 + random.nextDouble() * 0.011,
                -86.244 + random.nextDouble() * 0.016),
        ];
        final ordered = orderOpenRoute(start, points);
        expect(ordered.map((p) => p.id).toSet(), points.map((p) => p.id).toSet());
        final nn = orderOpenRoute(start, points, maxRefinePoints: 0);
        expect(routeLength(start, ordered),
            lessThanOrEqualTo(routeLength(start, nn) + 1e-6));
      }
    });

    test('points on a line are visited in order', () {
      const start = PlanPoint('s', 0, 0);
      final points = [
        const PlanPoint('c', 0, 0.003),
        const PlanPoint('a', 0, 0.001),
        const PlanPoint('b', 0, 0.002),
      ];
      expect(orderOpenRoute(start, points).map((p) => p.id), ['a', 'b', 'c']);
    });
  });
}
