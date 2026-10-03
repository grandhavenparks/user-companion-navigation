import 'package:edge_forestry_mobile/services/park_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _square = '[[[-93.04,45.34],[-93.02,45.34],[-93.02,45.36],[-93.04,45.36],[-93.04,45.34]]]';

void main() {
  test('name from file name', () {
    expect(parkNameFromFileName('MI_0005_GrandHavenParks.geojson'), 'Grand Haven Parks');
    expect(parkNameFromFileName('MI_0120_BassRiverRecreationArea.geojson'),
        'Bass River Recreation Area');
    expect(parkNameFromFileName('my_park-file.geojson'), 'my park file');
  });

  test('every feature becomes an area (two far-apart polygons)', () {
    final park = parseParkGeoJson('''
      {"type":"FeatureCollection","features":[
        {"type":"Feature","properties":{},"geometry":{"type":"Polygon","coordinates":$_square}},
        {"type":"Feature","properties":{},"geometry":{"type":"Polygon","coordinates":
          [[[-93.77,45.42],[-93.75,45.42],[-93.75,45.46],[-93.77,45.46],[-93.77,45.42]]]}}
      ]}''', fileName: 'MN_0001_Test.geojson');
    expect(park.areas, hasLength(2));
    expect(park.areaIndexAt(45.35, -93.03), 0);
    expect(park.areaIndexAt(45.44, -93.76), 1);
    expect(park.areaIndexAt(45.40, -93.40), isNull);
  });

  test('MultiPolygon with a hole and name property', () {
    final park = parseParkGeoJson('''
      {"type":"Feature","properties":{"name":"Forest Lake Oaks"},
       "geometry":{"type":"MultiPolygon","coordinates":[[
         [[-93.04,45.34],[-93.02,45.34],[-93.02,45.36],[-93.04,45.36],[-93.04,45.34]],
         [[-93.035,45.345],[-93.025,45.345],[-93.025,45.355],[-93.035,45.355],[-93.035,45.345]]
       ]]}}''', fileName: 'x.geojson');
    expect(park.name, 'Forest Lake Oaks');
    expect(park.containsPoint(45.341, -93.039), isTrue);
    expect(park.containsPoint(45.35, -93.03), isFalse, reason: 'inside the hole');
  });

  test('rejects [lat, lon] order with a hint', () {
    expect(
      () => parseParkGeoJson(
          '{"type":"Polygon","coordinates":[[[45.34,-93.04],[45.34,-93.02],[45.36,-93.02],[45.34,-93.04]]]}',
          fileName: 'bad.geojson'),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('[lon, lat]'))),
    );
  });

  test('point exactly on a vertex latitude is counted once', () {
    final park = parseParkGeoJson(
        '{"type":"Polygon","coordinates":[[[0,0],[2,1],[0,2],[1,1],[0,0]]]}',
        fileName: 'v.geojson');
    expect(park.containsPoint(1, 0.5), isFalse);
    expect(park.containsPoint(1, 1.5), isTrue);
  });
}
