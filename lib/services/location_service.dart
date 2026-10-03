import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';
import '../models/user_location.dart';

/// Location settings for the position stream.
///
/// On Android the fused provider is used with the requested update interval
/// and no distance filter, so the marker keeps moving smoothly even when you
/// walk slowly between trees.
LocationSettings buildLocationSettings(int intervalSeconds) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: Duration(seconds: intervalSeconds),
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 0,
  );
}

/// Converts a geolocator [Position] into the app model. The GPS course is
/// only trusted while moving; standing still it is meaningless.
UserLocation toUserLocation(Position position) {
  final speed = position.speed;
  final heading = position.heading;
  final moving = speed.isFinite && speed >= AppConfig.minSpeedForHeading;
  return UserLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    timestamp: position.timestamp,
    accuracy: position.accuracy,
    altitude: position.altitude,
    speed: speed,
    heading: moving && heading.isFinite && heading >= 0 ? heading : null,
  );
}
