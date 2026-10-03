import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// User preferences persisted with shared_preferences.
@immutable
class AppSettings {
  const AppSettings({
    this.useFeet = false,
    this.gpsIntervalSeconds = AppConfig.defaultGpsIntervalSeconds,
    this.arrivalRadiusMeters = AppConfig.defaultArrivalRadiusMeters,
  });

  final bool useFeet;
  final int gpsIntervalSeconds;
  final double arrivalRadiusMeters;

  AppSettings copyWith({
    bool? useFeet,
    int? gpsIntervalSeconds,
    double? arrivalRadiusMeters,
  }) {
    return AppSettings(
      useFeet: useFeet ?? this.useFeet,
      gpsIntervalSeconds: gpsIntervalSeconds ?? this.gpsIntervalSeconds,
      arrivalRadiusMeters: arrivalRadiusMeters ?? this.arrivalRadiusMeters,
    );
  }
}
