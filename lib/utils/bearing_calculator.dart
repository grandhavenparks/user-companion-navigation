import 'dart:math';

/// Bearing from point 1 to point 2 in degrees (0 = North, 90 = East).
double calculateBearing(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLon = (lon2 - lon1) * pi / 180;
  final lat1Rad = lat1 * pi / 180;
  final lat2Rad = lat2 * pi / 180;

  final y = sin(dLon) * cos(lat2Rad);
  final x = cos(lat1Rad) * sin(lat2Rad) -
      sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

  final bearing = atan2(y, x) * 180 / pi;
  return (bearing + 360) % 360;
}

/// Cardinal direction abbreviation from bearing (e.g. "NW", "E").
String bearingToCardinal(double bearing) {
  const directions = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  final index = ((bearing + 11.25) / 22.5).floor() % 16;
  return directions[index];
}

/// Format bearing for display (e.g. "315° NW").
String formatBearing(double bearing) {
  return '${bearing.round()}° ${bearingToCardinal(bearing)}';
}
