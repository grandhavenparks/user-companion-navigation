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
  static const _clusterArrivalRadiusKey = 'cluster_arrival_radius_m';
  static const _clusterViewKey = 'cluster_view';
  static const _activeRunKey = 'active_run_id';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      useFeet: prefs.getBool(_useFeetKey) ?? false,
      gpsIntervalSeconds: _pick(
        prefs.getInt(_gpsIntervalKey),
        AppConfig.gpsIntervalChoices,
        AppConfig.defaultGpsIntervalSeconds,
      ),
      arrivalRadiusMeters: _pick(
        prefs.getDouble(_arrivalRadiusKey),
        AppConfig.arrivalRadiusChoices,
        AppConfig.defaultArrivalRadiusMeters,
      ),
      clusterArrivalRadiusMeters: _pick(
        prefs.getDouble(_clusterArrivalRadiusKey),
        AppConfig.clusterArrivalRadiusChoices,
        AppConfig.defaultClusterArrivalRadiusMeters,
      ),
      clusterView: prefs.getBool(_clusterViewKey) ?? false,
      activeRunId: prefs.getString(_activeRunKey),
    );
  }

  static T _pick<T>(T? stored, List<T> choices, T fallback) =>
      stored != null && choices.contains(stored) ? stored : fallback;

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

  Future<void> setClusterArrivalRadiusMeters(double value) async {
    state = state.copyWith(clusterArrivalRadiusMeters: value);
    await _prefs.setDouble(_clusterArrivalRadiusKey, value);
  }

  Future<void> setClusterView(bool value) async {
    state = state.copyWith(clusterView: value);
    await _prefs.setBool(_clusterViewKey, value);
  }

  /// Makes [runId] the run shown on the map (null = most recent run).
  Future<void> setActiveRunId(String? runId) async {
    state = runId == null
        ? state.copyWith(clearActiveRunId: true)
        : state.copyWith(activeRunId: runId);
    if (runId == null) {
      await _prefs.remove(_activeRunKey);
    } else {
      await _prefs.setString(_activeRunKey, runId);
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
