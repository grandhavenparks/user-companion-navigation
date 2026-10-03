
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_location.dart';
import '../services/location_service.dart';

final locationStreamProvider = StreamProvider<UserLocation?>((ref) {
  return locationStream;
});

final currentLocationProvider = FutureProvider<UserLocation?>((ref) {
  return getCurrentLocation();
});
