import 'dart:convert';

import 'package:edge_forestry_mobile/services/csv_points_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

CsvPointsParseResult parse(String csv) => parsePointsCsv(csv, sourceName: 'test.csv');

void main() {
  group('column detection', () {
    test('oak wilt results file (lat, lon, filename, classification, confidence)', () {
      final r = parse(
        'filename,classification,confidence,lat,lon\n'
        'IMG_0266.jpg,THIS PICTURE HAS OAK WILT,99.99783,45.42969466388889,-93.76127741777778\n'
        'IMG_0303.jpg,THIS PICTURE HAS OAK WILT,100.0,45.3518660525,-93.02799565222222\n',
      );
      expect(r.success, isTrue, reason: r.error);
      expect(r.trees, hasLength(2));
      final t = r.trees!.first;
      expect(t.filename, 'IMG_0266.jpg');
      expect(t.classification, 'THIS PICTURE HAS OAK WILT');
      expect(t.predictionScore, closeTo(99.99783, 1e-9));
      expect(t.latitude, closeTo(45.4296946, 1e-6));
      expect(t.longitude, closeTo(-93.7612774, 1e-6));
      expect(r.report!.coordinateColumns, 'lat / lon');
    });

    test('Latitude/Longitude in capitals', () {
      final r = parse('Latitude,Longitude\n43.0516,-86.2414\n');
      expect(r.trees!.single.latitude, 43.0516);
    });

    for (final header in [
      'lat,lng', 'LAT,LONG', 'y,x', 'Y,X', 'POINT_Y,POINT_X', 'GPSLatitude,GPSLongitude',
      'gps_lat,gps_lon', 'decimalLatitude,decimalLongitude', 'Lat.,Lon.',
      'Latitude (deg),Longitude (deg)', 'lat_wgs84,lon_wgs84', '"lat","lon"',
      'Latitude_DD,Longitude_DD', 'tree_lat,tree_lon',
    ]) {
      test('header "$header"', () {
        final r = parse('$header\n45.1,-93.2\n');
        expect(r.success, isTrue, reason: r.error);
        expect(r.trees!.single.latitude, 45.1);
        expect(r.trees!.single.longitude, -93.2);
      });
    }

    test('prefers latitude/longitude over x/y', () {
      final r = parse('x,y,latitude,longitude\n500000,4900000,45.1,-93.2\n');
      expect(r.trees!.single.latitude, 45.1);
    });

    test('combined coordinate column and WKT', () {
      final r = parse('photo,coordinates\nimg1,"45.42, -93.76"\nimg2,POINT(-93.7 45.4)\n');
      expect(r.trees, hasLength(2));
      expect(r.trees![1].latitude, 45.4);
      expect(r.trees![1].longitude, -93.7);
    });

    test('missing columns gives a helpful error', () {
      final r = parse('a,b\n1,2\n');
      expect(r.success, isFalse);
      expect(r.error, contains('No latitude/longitude columns'));
    });
  });

  group('file formats', () {
    test('BOM, CRLF and quoted name with comma', () {
      final r = parse('\uFEFF"Lat","Long","Name"\r\n45.1,-93.2,"Oak, big"\r\n');
      expect(r.trees!.single.filename, 'Oak, big');
    });

    test('semicolon separated with decimal commas', () {
      final r = parse('id;lat;lon\n1;45,123;-93,456\n');
      expect(r.report!.delimiter, ';');
      expect(r.trees!.single.latitude, 45.123);
      expect(r.trees!.single.longitude, -93.456);
    });

    test('tab separated', () {
      final r = parse('lat\tlon\n45.1\t-93.1\n');
      expect(r.report!.delimiter, '\t');
      expect(r.trees, hasLength(1));
    });

    test('Latin-1 bytes fall back gracefully', () {
      final bytes = latin1.encode('lat,lon,name\n45.1,-93.1,Chêne\n');
      final r = parsePointsCsvBytes(bytes, sourceName: 'x.csv');
      expect(r.trees!.single.filename, 'Chêne');
    });
  });

  group('coordinate values', () {
    test('degrees minutes seconds and hemispheres', () {
      expect(parseCoordinateValue('45°25\'46.9"N'), closeTo(45.429694, 1e-5));
      expect(parseCoordinateValue('93°45\'40.6"W'), closeTo(-93.761278, 1e-5));
      expect(parseCoordinateValue('45 25 46.9'), closeTo(45.429694, 1e-5));
      expect(parseCoordinateValue('45d25m46.9s'), closeTo(45.429694, 1e-5));
      expect(parseCoordinateValue('45d25m46.9sS'), closeTo(-45.429694, 1e-5));
      expect(parseCoordinateValue('93.76 W'), -93.76);
      expect(parseCoordinateValue('N45.43'), 45.43);
      expect(parseCoordinateValue('\u221293.5'), -93.5);
    });

    test('rejects junk', () {
      expect(parseCoordinateValue(''), isNull);
      expect(parseCoordinateValue('NaN'), isNull);
      expect(parseCoordinateValue('Infinity'), isNull);
      expect(parseCoordinateValue('abc'), isNull);
      expect(parseCoordinateValue("45°60'"), isNull);
    });

    test('swaps reversed rows and skips bad ones with row numbers', () {
      final r = parse('lat,lon\n-93.76,45.42\n12,13\nNaN,1\n0,0\n,\n500,600\n');
      final report = r.report!;
      expect(report.swapped, 1);
      expect(r.trees, hasLength(2));
      expect(r.trees!.first.latitude, 45.42);
      expect(report.skipped['unreadable coordinates'], [4]);
      expect(report.skipped['0,0 coordinates'], [5]);
      expect(report.skipped['coordinates out of range'], [7]);
    });

    test('confidence formats', () {
      expect(parseConfidence('87%'), 87);
      expect(parseConfidence('0,87'), 0.87);
      expect(parseConfidence('n/a'), isNull);
    });
  });

  test('dataset name from file name', () {
    expect(datasetNameFromFile('oak_wilt_results_20261002_225155.csv'),
        'oak_wilt_results_20261002_225155');
  });
}
