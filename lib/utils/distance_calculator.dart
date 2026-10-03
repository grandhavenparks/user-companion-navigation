import 'dart:math';

/// Haversine formula - great-circle distance between two GPS points in meters.
double calculateDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const R = 6371e3; // Earth radius in meters
  final phi1 = lat1 * pi / 180;
  final phi2 = lat2 * pi / 180;
  final deltaPhi = (lat2 - lat1) * pi / 180;
  final deltaLambda = (lon2 - lon1) * pi / 180;

  final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
      cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c;
}

/// Format distance for display (meters or feet).
String formatDistance(double meters, {bool useFeet = false}) {
  if (useFeet) {
    final feet = meters * 3.28084;
    if (feet >= 5280) {
      final miles = feet / 5280;
      return '${miles.toStringAsFixed(1)} mi';
    }
    return '${feet.round()} ft';
  }
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}
