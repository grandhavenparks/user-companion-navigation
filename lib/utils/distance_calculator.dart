import 'dart:math';

/// Haversine formula - great-circle distance between two GPS points in metres.
double calculateDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371e3; // Earth radius in metres
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final deltaPhi = (lat2 - lat1) * pi / 180;
  final deltaLambda = (lon2 - lon1) * pi / 180;

  final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
      cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return r * c;
}

/// Format a distance for display in metres/kilometres or feet/miles.
String formatDistance(double meters, {bool useFeet = false}) {
  if (useFeet) {
    final feet = meters * 3.28084;
    if (feet >= 5280) {
      return '${(feet / 5280).toStringAsFixed(1)} mi';
    }
    return '${feet.round()} ft';
  }
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km';
  }
  if (meters < 10) {
    return '${meters.toStringAsFixed(1)} m';
  }
  return '${meters.round()} m';
}
