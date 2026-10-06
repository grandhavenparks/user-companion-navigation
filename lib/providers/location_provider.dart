import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user_location.dart';
import '../services/location_service.dart';
import 'settings_provider.dart';

enum LocationStatus {
  starting,
  ready,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

@immutable
class LocationState {
  const LocationState({
    this.status = LocationStatus.starting,
    this.location,
    this.approximate = false,
    this.message,
  });

  final LocationStatus status;

  /// Last known fix (kept while the stream restarts).
  final UserLocation? location;

  /// The user granted only "approximate" location (Android 12+).
  final bool approximate;
  final String? message;

  LocationState copyWith({
    LocationStatus? status,
    UserLocation? location,
    bool? approximate,
    String? message,
    bool clearMessage = false,
  }) {
    return LocationState(
      status: status ?? this.status,
      location: location ?? this.location,
      approximate: approximate ?? this.approximate,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Owns the GPS stream while a map or point screen is open.
///
/// * Stops listening when the app goes to the background (no tracking with
///   the screen off) and restarts with a fresh fix when it comes back, so the
///   route is recomputed for wherever the user is now.
/// * Restarts when location services are switched back on or the update
///   interval changes in Settings.
class LocationController extends AutoDisposeNotifier<LocationState>
    with WidgetsBindingObserver {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  int _intervalSeconds = 1;
  bool _disposed = false;
  bool _starting = false;
  bool _restartPending = false;

  @override
  LocationState build() {
    _disposed = false;
    ref.listen<int>(
      settingsProvider.select((s) => s.gpsIntervalSeconds),
      (previous, next) {
        _intervalSeconds = next;
        if (previous != null && previous != next) unawaited(restart());
      },
      fireImmediately: true,
    );
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _positionSub?.cancel();
      _serviceSub?.cancel();
    });
    Future.microtask(restart);
    return const LocationState();
  }

  /// (Re)starts the position stream, asking for permission when needed.
  Future<void> restart() async {
    if (_disposed) return;
    if (_starting) {
      _restartPending = true;
      return;
    }
    _starting = true;
    try {
      await _stopStream();
      _serviceSub ??= _listenServiceStatus();

      if (!await Geolocator.isLocationServiceEnabled()) {
        _update((s) => s.copyWith(status: LocationStatus.serviceDisabled));
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _update((s) => s.copyWith(status: LocationStatus.permissionDeniedForever));
        return;
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _update((s) => s.copyWith(status: LocationStatus.permissionDenied));
        return;
      }

      final accuracy = await Geolocator.getLocationAccuracy();
      if (_disposed) return;
      _update((s) => s.copyWith(
        status: LocationStatus.ready,
        approximate: accuracy == LocationAccuracyStatus.reduced,
        clearMessage: true,
      ));

      _positionSub = Geolocator.getPositionStream(
        locationSettings: buildLocationSettings(_intervalSeconds),
      ).listen(_onPosition, onError: _onError);
    } catch (e) {
      _update((s) => s.copyWith(status: LocationStatus.unavailable, message: '$e'));
    } finally {
      _starting = false;
      if (_restartPending && !_disposed) {
        _restartPending = false;
        unawaited(restart());
      }
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(restart());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopStream());
    }
  }

  StreamSubscription<ServiceStatus>? _listenServiceStatus() {
    try {
      return Geolocator.getServiceStatusStream().listen(
        (status) {
          if (status == ServiceStatus.enabled) {
            unawaited(restart());
          } else {
            unawaited(_stopStream());
            _update((s) => s.copyWith(status: LocationStatus.serviceDisabled));
          }
        },
        onError: (Object _) {},
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _stopStream() async {
    final sub = _positionSub;
    _positionSub = null;
    await sub?.cancel();
  }

  void _onPosition(Position position) {
    _update((s) => s.copyWith(
      status: LocationStatus.ready,
      location: toUserLocation(position),
      clearMessage: true,
    ));
  }

  void _onError(Object error) {
    unawaited(_stopStream());
    if (error is LocationServiceDisabledException) {
      _update((s) => s.copyWith(status: LocationStatus.serviceDisabled));
    } else if (error is PermissionDeniedException) {
      _update((s) => s.copyWith(status: LocationStatus.permissionDenied));
    } else {
      _update((s) => s.copyWith(status: LocationStatus.unavailable, message: '$error'));
    }
  }

  /// Updates the state unless the provider was disposed meanwhile (the
  /// position stream and permission dialogs are asynchronous).
  void _update(LocationState Function(LocationState current) change) {
    if (_disposed) return;
    state = change(state);
  }
}

final locationControllerProvider =
    NotifierProvider.autoDispose<LocationController, LocationState>(
  LocationController.new,
);