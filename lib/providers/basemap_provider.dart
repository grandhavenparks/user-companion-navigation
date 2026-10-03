import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/basemap_service.dart';

/// The bundled offline basemap; installed and opened once per app session.
final basemapProvider = FutureProvider<Basemap>((ref) {
  return BasemapService.instance.load();
});
