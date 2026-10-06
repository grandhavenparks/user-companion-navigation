import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// User preferences persisted with shared_preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.useFeet = false,
    this.gpsIntervalSeconds = AppConfig.defaultGpsIntervalSeconds,
    this.arrivalRadiusMeters = AppConfig.defaultArrivalRadiusMeters,
    this.clusterArrivalRadiusMeters = AppConfig.defaultClusterArrivalRadiusMeters,
    this.clusterView = false,
    this.activeRunId,
  });

  final bool useFeet;
  final int gpsIntervalSeconds;

  /// "Arrived" distance for normal points.
  final double arrivalRadiusMeters;

  /// "Arrived" distance for clusters.
  final double clusterArrivalRadiusMeters;

  /// Map shows clusters instead of points (remembered across restarts).
  final bool clusterView;

  /// Run (imported CSV) used on the map. Null = most recently imported run.
  final String? activeRunId;

  AppSettings copyWith({
    bool? useFeet,
    int? gpsIntervalSeconds,
    double? arrivalRadiusMeters,
    double? clusterArrivalRadiusMeters,
    bool? clusterView,
    String? activeRunId,
    bool clearActiveRunId = false,
  }) {
    return AppSettings(
      useFeet: useFeet ?? this.useFeet,
      gpsIntervalSeconds: gpsIntervalSeconds ?? this.gpsIntervalSeconds,
      arrivalRadiusMeters: arrivalRadiusMeters ?? this.arrivalRadiusMeters,
      clusterArrivalRadiusMeters:
          clusterArrivalRadiusMeters ?? this.clusterArrivalRadiusMeters,
      clusterView: clusterView ?? this.clusterView,
      activeRunId: clearActiveRunId ? null : (activeRunId ?? this.activeRunId),
    );
  }
}
