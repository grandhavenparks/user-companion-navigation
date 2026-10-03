import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Current user GPS position and metadata.
@immutable
class UserLocation {
  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.altitude,
    this.heading,
    this.speed,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Horizontal accuracy radius in metres.
  final double? accuracy;
  final double? altitude;

  /// Direction of travel in degrees (0 = north); null when standing still.
  final double? heading;

  /// Speed in m/s.
  final double? speed;

  LatLng get position => LatLng(latitude, longitude);

  @override
  bool operator ==(Object other) =>
      other is UserLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timestamp == timestamp &&
      other.accuracy == accuracy &&
      other.heading == heading;

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, timestamp, accuracy, heading);
}
