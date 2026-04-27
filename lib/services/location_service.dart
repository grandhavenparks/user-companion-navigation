import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/user_location.dart';

// FAKE LOCATION FOR TESTING - Set to true to use fake location
const bool _useFakeLocation = false; // Using real GPS location

// Fake location coordinates - Walker Park, Michigan (center of park)
const double _fakeLatitude = 42.969234;
const double _fakeLongitude = -85.756081;

/// Stream of user locations; null when permission denied or error.
Stream<UserLocation?> get locationStream async* {
  if (_useFakeLocation) {
    // Emit fake location for testing
    yield UserLocation(
      latitude: _fakeLatitude,
      longitude: _fakeLongitude,
      accuracy: 10.0,
      altitude: 0,
      heading: 0,
      timestamp: DateTime.now(),
    );
    
    // Keep emitting the same location periodically to simulate updates
    await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
      yield UserLocation(
        latitude: _fakeLatitude,
        longitude: _fakeLongitude,
        accuracy: 10.0,
        altitude: 0,
        heading: 0,
        timestamp: DateTime.now(),
      );
    }
    return;
  }
  
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    final requested = await Geolocator.requestPermission();
    if (requested != LocationPermission.whileInUse &&
        requested != LocationPermission.always) {
      yield null;
      return;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    yield null;
    return;
  }

  final settings = const LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5,
  );

  await for (final pos in Geolocator.getPositionStream(
    locationSettings: settings,
  )) {
    yield UserLocation(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      heading: pos.heading,
      timestamp: pos.timestamp,
    );
  }
}

/// Get current position once.
Future<UserLocation?> getCurrentLocation() async {
  if (_useFakeLocation) {
    return UserLocation(
      latitude: _fakeLatitude,
      longitude: _fakeLongitude,
      accuracy: 10.0,
      altitude: 0,
      heading: 0,
      timestamp: DateTime.now(),
    );
  }
  
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    final requested = await Geolocator.requestPermission();
    if (requested != LocationPermission.whileInUse &&
        requested != LocationPermission.always) {
      return null;
    }
  }
  if (permission == LocationPermission.deniedForever) return null;

  try {
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
    return UserLocation(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      heading: pos.heading,
      timestamp: pos.timestamp,
    );
  } catch (_) {
    return null;
  }
}
