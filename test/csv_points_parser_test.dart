import 'dart:convert';

import 'package:user_navigation_companion/models/dataset.dart';
import 'package:user_navigation_companion/models/tree.dart';
import 'package:user_navigation_companion/services/csv_points_parser_service.dart';
import 'package:user_navigation_companion/services/visited_points_export_service.dart';
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

  group('cluster files (cluster view only)', () {
    const oldAppExport =
        'count,latitude,longitude,avg_confidence,dominant_classification,dominant_predicted_class\n'
        '5,43.05,-86.23,99.50,THIS PICTURE HAS OAK WILT,\n'
        '1,43.06,-86.24,,,\n';

    test('old app aggregated CSV imports as clusters without confidence', () {
      final r = parsePointsCsv(oldAppExport,
          sourceName: 'aggregated_points.csv', clusters: true, parentRunId: 'run1');
      expect(r.success, isTrue, reason: r.error);
      final first = r.trees!.first;
      expect(first.memberCount, 5);
      expect(first.classification, 'THIS PICTURE HAS OAK WILT');
      expect(first.predictionScore, isNull);
      expect(first.filename, 'Cluster 1 (5 trees)');
      expect(r.trees![1].filename, 'Cluster 2 (1 tree)');
      expect(r.dataset!.kind, DatasetKind.clusters);
      expect(r.dataset!.parentId, 'run1');
    });

    test('a cluster file is refused on Home (point import)', () {
      final r = parsePointsCsv(oldAppExport, sourceName: 'aggregated_points.csv');
      expect(r.success, isFalse);
      expect(r.error, contains('cluster file'));
    });

    test('a plain points file is refused in cluster view', () {
      final r = parsePointsCsv('lat,lon\n45.1,-93.1\n',
          sourceName: 'points.csv', clusters: true, parentRunId: 'run1');
      expect(r.success, isFalse);
      expect(r.error, contains('points file'));
    });

    test('visited export round-trips: points on Home, clusters in cluster view', () {
      final csv = buildVisitedCsv(
        runName: 'oak run',
        points: const [
          Tree(
            id: 'p',
            datasetId: 'run',
            filename: 'IMG_1.jpg',
            latitude: 43.05,
            longitude: -86.23,
            classification: 'OAK',
            predictionScore: 99.1,
            visited: true,
          ),
        ],
        clusters: const [
          Tree(
            id: 'c',
            datasetId: 'set',
            filename: 'Cluster 1 (2 trees)',
            latitude: 43.051,
            longitude: -86.231,
            classification: 'OAK',
            memberCount: 2,
            members: ['IMG_1.jpg', 'IMG_2.jpg'],
            visited: true,
          ),
        ],
      );
      final points = parsePointsCsv(csv, sourceName: 'visited.csv');
      expect(points.trees!.single.filename, 'IMG_1.jpg');
      expect(points.trees!.single.predictionScore, 99.1);
      expect(points.report!.otherTypeRows, 1);

      final clusters = parsePointsCsv(csv,
          sourceName: 'visited.csv', clusters: true, parentRunId: 'run');
      final c = clusters.trees!.single;
      expect(c.memberCount, 2);
      expect(c.members, ['IMG_1.jpg', 'IMG_2.jpg']);
      expect(c.filename, 'Cluster 1 (2 trees)');
      expect(c.predictionScore, isNull);
      expect(c.visited, isFalse, reason: 'imports always start unvisited');
    });

    test('a "type" column with other values is an ordinary column', () {
      final r = parsePointsCsv('lat,lon,type\n45.1,-93.1,oak\n', sourceName: 'x.csv');
      expect(r.trees, hasLength(1));
    });
  });
}
