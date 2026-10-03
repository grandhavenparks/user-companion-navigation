import 'dart:io';
import 'dart:typed_data';

import 'package:user_navigation_companion/services/basemap_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MBTiles rows are TMS (flipped y)', () {
    expect(tmsRow(0, 0), 0);
    expect(tmsRow(1, 0), 1);
    expect(tmsRow(15, 0), 32767);
    expect(tmsRow(15, 32767), 0);
  });

  test('gzip tiles are decompressed, plain tiles passed through', () {
    final plain = Uint8List.fromList([1, 2, 3, 4]);
    expect(decodeTileData(plain), plain);
    final zipped = Uint8List.fromList(gzip.encode(plain));
    expect(decodeTileData(zipped), plain);
  });

  test('manifest parsing', () {
    final m = MapManifest.fromJson({
      'build_id': 'abc',
      'min_zoom': 0,
      'max_zoom': 15,
      'created_utc': '2026-10-03T03:52:29+00:00',
      'parks': [
        {'file': 'a.geojson', 'name': 'Park A'},
      ],
    });
    expect(m.buildId, 'abc');
    expect(m.maxZoom, 15);
    expect(m.parkNames, ['Park A']);
    expect(m.createdUtc, isNotNull);
  });
}
