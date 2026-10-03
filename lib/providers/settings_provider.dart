import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/app_settings.dart';

/// Overridden in `main()` with the instance loaded before `runApp`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider is set in main()'),
);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _useFeetKey = 'use_feet';
  static const _gpsIntervalKey = 'gps_interval_seconds';
  static const _arrivalRadiusKey = 'arrival_radius_m';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    var interval =
        prefs.getInt(_gpsIntervalKey) ?? AppConfig.defaultGpsIntervalSeconds;
    if (!AppConfig.gpsIntervalChoices.contains(interval)) {
      interval = AppConfig.defaultGpsIntervalSeconds;
    }
    var radius =
        prefs.getDouble(_arrivalRadiusKey) ?? AppConfig.defaultArrivalRadiusMeters;
    if (!AppConfig.arrivalRadiusChoices.contains(radius)) {
      radius = AppConfig.defaultArrivalRadiusMeters;
    }
    return AppSettings(
      useFeet: prefs.getBool(_useFeetKey) ?? false,
      gpsIntervalSeconds: interval,
      arrivalRadiusMeters: radius,
    );
  }

  Future<void> setUseFeet(bool value) async {
    state = state.copyWith(useFeet: value);
    await _prefs.setBool(_useFeetKey, value);
  }

  Future<void> setGpsIntervalSeconds(int value) async {
    state = state.copyWith(gpsIntervalSeconds: value);
    await _prefs.setInt(_gpsIntervalKey, value);
  }

  Future<void> setArrivalRadiusMeters(double value) async {
    state = state.copyWith(arrivalRadiusMeters: value);
    await _prefs.setDouble(_arrivalRadiusKey, value);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
