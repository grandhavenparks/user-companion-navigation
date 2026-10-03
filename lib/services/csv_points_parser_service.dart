import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/dataset.dart';
import '../models/tree.dart';
import 'cluster_service.dart' show clusterName;

// ---------------------------------------------------------------------------
// Header aliases. Headers are compared in "compact" form: lower case, units in
// brackets removed, everything except a-z/0-9 removed. "GPS Latitude (deg)"
// -> "gpslatitude". Lists are in priority order.
// ---------------------------------------------------------------------------

const List<String> _latitudeAliases = [
  'latitude', 'lat', 'latdd', 'latitudedd', 'decimallatitude', 'declat',
  'latdec', 'latdecimal', 'latitudedecimal', 'gpslatitude', 'gpslat',
  'latwgs84', 'latitudewgs84', 'wgs84lat', 'wgs84latitude', 'latdeg',
  'latitudedeg', 'latitudedegrees', 'ylat', 'pointy', 'ycoord',
  'ycoordinate', 'y',
];

const List<String> _longitudeAliases = [
  'longitude', 'lon', 'lng', 'long', 'londd', 'lngdd', 'longdd',
  'longitudedd', 'decimallongitude', 'declon', 'declng', 'declong', 'londec',
  'londecimal', 'longitudedecimal', 'gpslongitude', 'gpslon', 'gpslng',
  'gpslong', 'lonwgs84', 'lngwgs84', 'longitudewgs84', 'wgs84lon', 'wgs84lng',
  'wgs84longitude', 'londeg', 'lngdeg', 'longitudedeg', 'longitudedegrees',
  'xlon', 'pointx', 'xcoord', 'xcoordinate', 'x',
];

/// A single column holding both values, e.g. "45.42, -93.76" or WKT POINT.
const List<String> _combinedAliases = [
  'coordinates', 'coordinate', 'coords', 'latlon', 'latlng', 'latlong',
  'lonlat', 'lnglat', 'longlat', 'location', 'position', 'point', 'gps',
  'geometry', 'geom', 'wkt',
];

const List<String> _nameAliases = [
  'filename', 'file', 'imagefilename', 'imagename', 'image', 'img', 'photo',
  'photoname', 'picture', 'name', 'pointname', 'treename', 'pointid',
  'treeid', 'id', 'title',
];

const List<String> _confidenceAliases = [
  'confidence', 'confidencescore', 'predictionconfidence', 'score',
  'probability', 'prob', 'predictionscore', 'conf', 'certainty',
];

const List<String> _classificationAliases = [
  'classification', 'dominantclassification', 'class', 'predictedclass', 'prediction',
  'predictedlabel', 'label', 'result', 'status', 'category', 'diagnosis',
  'disease',
];

const List<String> _descriptionAliases = [
  'description', 'notes', 'note', 'comment', 'comments', 'remarks', 'remark',
];

/// Row type in files exported by the app: `point` or `cluster`.
const List<String> _typeAliases = ['type', 'rowtype', 'pointtype', 'recordtype', 'kind'];

/// Cluster files: number of merged points.
const List<String> _countAliases = [
  'count', 'membercount', 'memberscount', 'treecount', 'trees', 'numtrees',
  'pointcount', 'numpoints',
];

/// Cluster files: names of the merged points, separated by ; | or new lines.
const List<String> _membersAliases = [
  'members', 'membernames', 'memberfilenames', 'memberfiles', 'filenames',
];

const Set<String> _latitudeTokens = {'lat', 'latitude'};
const Set<String> _longitudeTokens = {'lon', 'lng', 'long', 'longitude'};

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// What happened during an import, shown to the user afterwards.
class CsvImportReport {
  CsvImportReport({
    required this.delimiter,
    required this.coordinateColumns,
    this.clusters = false,
    this.nameColumn,
    this.classificationColumn,
    this.confidenceColumn,
    this.descriptionColumn,
    this.countColumn,
    this.membersColumn,
  });

  /// The file was imported as clusters (cluster view).
  final bool clusters;
  final String? countColumn;
  final String? membersColumn;

  /// Rows of the other type (`type` column) that were left out.
  int otherTypeRows = 0;

  final String delimiter;

  /// e.g. "lat / lon" or "coordinates (combined)".
  final String coordinateColumns;
  final String? nameColumn;
  final String? classificationColumn;
  final String? confidenceColumn;
  final String? descriptionColumn;

  int dataRows = 0;
  int imported = 0;
  int swapped = 0;

  /// reason -> row numbers as in the file (1-based, header is row 1).
  final Map<String, List<int>> skipped = {};
  final List<String> warnings = [];

  int get skippedTotal => skipped.values.fold(0, (sum, rows) => sum + rows.length);

  String get delimiterLabel => switch (delimiter) {
        ',' => 'comma',
        ';' => 'semicolon',
        '\t' => 'tab',
        '|' => 'pipe',
        _ => delimiter,
      };

  void _skip(String reason, int row) => skipped.putIfAbsent(reason, () => []).add(row);

  /// Short human readable lines for a dialog.
  List<String> summaryLines() {
    final noun = clusters ? 'clusters' : 'rows';
    final lines = <String>[
      'Imported $imported of $dataRows $noun ($delimiterLabel separated).',
      'Coordinates: $coordinateColumns.',
    ];
    final extra = <String>[
      if (nameColumn != null) 'name: $nameColumn',
      if (classificationColumn != null) 'classification: $classificationColumn',
      if (confidenceColumn != null) 'confidence: $confidenceColumn',
      if (descriptionColumn != null) 'notes: $descriptionColumn',
      if (countColumn != null) 'count: $countColumn',
      if (membersColumn != null) 'members: $membersColumn',
    ];
    if (extra.isNotEmpty) lines.add('Also read ${extra.join(', ')}.');
    if (otherTypeRows > 0) {
      lines.add(clusters
          ? 'Left out $otherTypeRows point row(s); import points on Home.'
          : 'Left out $otherTypeRows cluster row(s); import those on the map '
              'in cluster view.');
    }
    if (swapped > 0) {
      lines.add('Swapped latitude/longitude in $swapped row(s).');
    }
    for (final entry in skipped.entries) {
      final rows = entry.value;
      final shown = rows.take(5).join(', ');
      final more = rows.length > 5 ? ', ...' : '';
      lines.add('Skipped ${rows.length} row(s): ${entry.key} (row $shown$more).');
    }
    lines.addAll(warnings);
    return lines;
  }
}

class CsvPointsParseResult {
  const CsvPointsParseResult({
    this.dataset,
    this.trees,
    this.report,
    this.error,
  });

  final Dataset? dataset;
  final List<Tree>? trees;
  final CsvImportReport? report;
  final String? error;

  bool get success => error == null && dataset != null && trees != null;
}

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

/// Parses raw file bytes (UTF-8 with or without BOM, falls back to Latin-1).
///
/// With [clusters] the file is read as a cluster file (cluster view only):
/// count/members columns are read, confidence is ignored and the dataset
/// becomes the cluster set of [parentRunId].
CsvPointsParseResult parsePointsCsvBytes(
  List<int> bytes, {
  required String sourceName,
  DateTime? importedAt,
  bool clusters = false,
  String? parentRunId,
}) {
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes, allowInvalid: true);
  }
  return parsePointsCsv(
    text,
    sourceName: sourceName,
    importedAt: importedAt,
    clusters: clusters,
    parentRunId: parentRunId,
  );
}

/// Parses CSV/TSV text into a [Dataset] and its points.
CsvPointsParseResult parsePointsCsv(
  String content, {
  required String sourceName,
  DateTime? importedAt,
  bool clusters = false,
  String? parentRunId,
}) {
  var text = content;
  if (text.startsWith('\uFEFF')) text = text.substring(1);

  final delimiter = detectDelimiter(text);
  // Keep the original line numbers so skipped rows can be found in the file.
  final allRows = parseCsvRows(text, delimiter);
  final rows = <List<String>>[];
  final rowNumbers = <int>[];
  for (var i = 0; i < allRows.length; i++) {
    if (allRows[i].any((cell) => cell.trim().isNotEmpty)) {
      rows.add(allRows[i]);
      rowNumbers.add(i + 1);
    }
  }
  if (rows.length < 2) {
    return const CsvPointsParseResult(
      error: 'The file needs a header row and at least one data row.',
    );
  }

  final header = rows.first.map(_cleanHeader).toList();
  final data = rows.sublist(1);
  final dataRowNumbers = rowNumbers.sublist(1);
  final compact = header.map(compactHeader).toList();
  final tokens = header.map(headerTokens).toList();
  final taken = <int>{};

  int? find(List<String> aliases) {
    for (final alias in aliases) {
      for (var i = 0; i < compact.length; i++) {
        if (!taken.contains(i) && compact[i] == alias) {
          taken.add(i);
          return i;
        }
      }
    }
    return null;
  }

  int? findByToken(Set<String> wanted) {
    for (var i = 0; i < tokens.length; i++) {
      if (taken.contains(i)) continue;
      if (tokens[i].any(wanted.contains) && _mostlyCoordinates(data, i)) {
        taken.add(i);
        return i;
      }
    }
    return null;
  }

  var latIndex = find(_latitudeAliases);
  var lonIndex = find(_longitudeAliases);
  latIndex ??= findByToken(_latitudeTokens);
  lonIndex ??= findByToken(_longitudeTokens);

  int? combinedIndex;
  var combinedLonFirst = false;
  if (latIndex == null || lonIndex == null) {
    if (latIndex != null) taken.remove(latIndex);
    if (lonIndex != null) taken.remove(lonIndex);
    latIndex = null;
    lonIndex = null;
    combinedIndex = find(_combinedAliases);
    if (combinedIndex != null) {
      final c = compact[combinedIndex];
      combinedLonFirst = c.startsWith('lon') || c.startsWith('lng');
    }
  }

  if (combinedIndex == null && (latIndex == null || lonIndex == null)) {
    final shown = header.where((h) => h.isNotEmpty).take(12).join(', ');
    return CsvPointsParseResult(
      error: 'No latitude/longitude columns found. Columns in the file: '
          '$shown. Expected names like latitude/lat/y and longitude/lon/lng/x.',
    );
  }

  var typeIndex = find(_typeAliases);
  if (typeIndex != null && !_isRowTypeColumn(data, typeIndex)) {
    // A column called e.g. "type" or "kind" holding something else.
    taken.remove(typeIndex);
    typeIndex = null;
  }
  final countIndex = find(_countAliases);
  final membersIndex = find(_membersAliases);

  // Cluster files may only be imported in cluster view, and cluster view only
  // takes cluster files.
  final hasClusterColumns = countIndex != null &&
      (membersIndex != null || compact.contains('dominantclassification'));
  if (!clusters && typeIndex == null && hasClusterColumns) {
    return const CsvPointsParseResult(
      error: 'This looks like a cluster file. Import it on the map in cluster '
          'view (cluster menu > Import cluster CSV).',
    );
  }
  if (clusters && typeIndex == null && countIndex == null && membersIndex == null) {
    return const CsvPointsParseResult(
      error: 'This looks like a points file (no count, members or type '
          'column). Import points on Home, or use "Create clusters" on the map.',
    );
  }

  final nameIndex = find(_nameAliases);
  // Clusters never carry a confidence score.
  final confidenceIndex = clusters ? null : find(_confidenceAliases);
  final classificationIndex = find(_classificationAliases);
  final descriptionIndex = find(_descriptionAliases);
  final wantedType = clusters ? 'cluster' : 'point';

  final report = CsvImportReport(
    delimiter: delimiter,
    clusters: clusters,
    countColumn: clusters && countIndex != null ? header[countIndex] : null,
    membersColumn: clusters && membersIndex != null ? header[membersIndex] : null,
    coordinateColumns: combinedIndex != null
        ? '${header[combinedIndex]} (combined)'
        : '${header[latIndex!]} / ${header[lonIndex!]}',
    nameColumn: nameIndex == null ? null : header[nameIndex],
    classificationColumn:
        classificationIndex == null ? null : header[classificationIndex],
    confidenceColumn: confidenceIndex == null ? null : header[confidenceIndex],
    descriptionColumn: descriptionIndex == null ? null : header[descriptionIndex],
  );

  const uuid = Uuid();
  final datasetId = uuid.v4();
  final trees = <Tree>[];

  for (var r = 0; r < data.length; r++) {
    final row = data[r];
    final rowNumber = dataRowNumbers[r];
    if (typeIndex != null) {
      final type = _cell(row, typeIndex).trim().toLowerCase();
      if (type.isNotEmpty && type != wantedType) {
        report.otherTypeRows++;
        continue;
      }
    }
    report.dataRows++;

    double? lat;
    double? lon;
    if (combinedIndex != null) {
      final pair = parseCombinedCoordinate(_cell(row, combinedIndex));
      if (pair == null) {
        report._skip(_cell(row, combinedIndex).trim().isEmpty
            ? 'missing coordinates'
            : 'unreadable coordinates', rowNumber);
        continue;
      }
      if (pair.isWkt || combinedLonFirst) {
        lon = pair.first;
        lat = pair.second;
      } else {
        lat = pair.first;
        lon = pair.second;
      }
    } else {
      final latRaw = _cell(row, latIndex!);
      final lonRaw = _cell(row, lonIndex!);
      if (latRaw.trim().isEmpty || lonRaw.trim().isEmpty) {
        report._skip('missing coordinates', rowNumber);
        continue;
      }
      lat = parseCoordinateValue(latRaw);
      lon = parseCoordinateValue(lonRaw);
      if (lat == null || lon == null) {
        report._skip('unreadable coordinates', rowNumber);
        continue;
      }
    }

    if (!_isLatitude(lat) || !_isLongitude(lon)) {
      if (_isLatitude(lon) && _isLongitude(lat)) {
        final t = lat;
        lat = lon;
        lon = t;
        report.swapped++;
      } else {
        report._skip('coordinates out of range', rowNumber);
        continue;
      }
    }
    if (lat == 0 && lon == 0) {
      report._skip('0,0 coordinates', rowNumber);
      continue;
    }

    final name = nameIndex == null ? '' : _cell(row, nameIndex).trim();
    final classification =
        classificationIndex == null ? '' : _cell(row, classificationIndex).trim();
    final description =
        descriptionIndex == null ? '' : _cell(row, descriptionIndex).trim();
    final confidence =
        confidenceIndex == null ? null : parseConfidence(_cell(row, confidenceIndex));

    if (clusters) {
      final members = membersIndex == null
          ? const <String>[]
          : _cell(row, membersIndex)
              .split(RegExp(r'[;|\n]'))
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty)
              .toList();
      final count = (countIndex == null ? null : parseCount(_cell(row, countIndex))) ??
          members.length;
      trees.add(Tree(
        id: uuid.v4(),
        datasetId: datasetId,
        filename: name.isNotEmpty ? name : clusterName(trees.length + 1, count),
        latitude: lat,
        longitude: lon,
        classification: classification.isEmpty ? null : classification,
        description: description.isEmpty ? null : description,
        memberCount: count,
        members: members,
      ));
    } else {
      trees.add(Tree(
        id: uuid.v4(),
        datasetId: datasetId,
        filename: name.isNotEmpty ? name : 'Point ${trees.length + 1}',
        latitude: lat,
        longitude: lon,
        classification: classification.isEmpty ? null : classification,
        description: description.isEmpty ? null : description,
        predictionScore: confidence,
      ));
    }
    report.imported++;
  }

  if (report.swapped > 0 && report.swapped == report.imported) {
    report.warnings.add(
        'Every row had latitude and longitude the wrong way round; they were corrected.');
  }
  if (report.dataRows > 0 && report.skippedTotal * 2 > report.dataRows) {
    report.warnings.add('Most rows were skipped. Coordinates must be WGS84 '
        'decimal degrees (or degrees/minutes/seconds), not UTM or other projections.');
  }

  if (trees.isEmpty) {
    if (report.dataRows == 0 && report.otherTypeRows > 0) {
      return CsvPointsParseResult(
        report: report,
        error: clusters
            ? 'This file has only point rows. Import it on Home, or use '
                '"Create clusters" on the map.'
            : 'This file has only cluster rows. Import it on the map in '
                'cluster view (cluster menu > Import cluster CSV).',
      );
    }
    return CsvPointsParseResult(
      report: report,
      error: 'No valid ${clusters ? 'clusters' : 'points'} found. '
          '${report.summaryLines().skip(1).join(' ')}',
    );
  }

  final baseName = datasetNameFromFile(sourceName);
  final dataset = Dataset(
    id: datasetId,
    name: clusters ? '$baseName · clusters' : baseName,
    treeCount: trees.length,
    importedAt: importedAt ?? DateTime.now(),
    kind: clusters ? DatasetKind.clusters : DatasetKind.points,
    parentId: clusters ? parentRunId : null,
  );
  return CsvPointsParseResult(dataset: dataset, trees: trees, report: report);
}

// ---------------------------------------------------------------------------
// Helpers (public so they can be unit tested)
// ---------------------------------------------------------------------------

/// Picks the delimiter that occurs most often (outside quotes) in the header.
String detectDelimiter(String text) {
  final newline = text.indexOf(RegExp(r'[\r\n]'));
  final line = newline == -1 ? text : text.substring(0, newline);
  const candidates = [',', ';', '\t', '|'];
  var best = ',';
  var bestCount = 0;
  for (final candidate in candidates) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && ch == candidate) {
        count++;
      }
    }
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return best;
}

/// RFC 4180 style parser: quoted fields, doubled quotes, delimiters and line
/// breaks inside quotes, CRLF/LF/CR line endings. A quote that does not start
/// a field is kept as a normal character (e.g. 45°25'46"N).
List<List<String>> parseCsvRows(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var atFieldStart = true;
  final n = text.length;
  var i = 0;
  while (i < n) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < n && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"' && atFieldStart) {
      inQuotes = true;
      atFieldStart = false;
      i++;
      continue;
    }
    if (ch == delimiter) {
      row.add(field.toString());
      field.clear();
      atFieldStart = true;
      i++;
      continue;
    }
    if (ch == '\n' || ch == '\r') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
      atFieldStart = true;
      if (ch == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
      i++;
      continue;
    }
    field.write(ch);
    atFieldStart = false;
    i++;
  }
  if (inQuotes || field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String _cleanHeader(String raw) {
  var h = raw.replaceAll('\uFEFF', '').trim();
  if (h.length >= 2 && h.startsWith('"') && h.endsWith('"')) {
    h = h.substring(1, h.length - 1).trim();
  }
  return h;
}

final RegExp _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]');

/// "GPS Latitude (deg)" -> "gpslatitude".
String compactHeader(String header) => header
    .replaceAll(_bracketed, '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// "treeLat_WGS84" -> ["tree", "lat", "wgs84"].
List<String> headerTokens(String header) => header
    .replaceAll(_bracketed, ' ')
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((t) => t.isNotEmpty)
    .toList();

String _cell(List<String> row, int index) => index < row.length ? row[index] : '';

/// True when every non-empty value is `point` or `cluster` (app export).
bool _isRowTypeColumn(List<List<String>> rows, int index) {
  var any = false;
  for (final row in rows) {
    final v = _cell(row, index).trim().toLowerCase();
    if (v.isEmpty) continue;
    if (v != 'point' && v != 'cluster') return false;
    any = true;
  }
  return any;
}

bool _isLatitude(double v) => v >= -90 && v <= 90;
bool _isLongitude(double v) => v >= -180 && v <= 180;

bool _mostlyCoordinates(List<List<String>> rows, int index) {
  var checked = 0;
  var ok = 0;
  for (final row in rows) {
    final value = _cell(row, index).trim();
    if (value.isEmpty) continue;
    checked++;
    if (parseCoordinateValue(value) != null) ok++;
    if (checked >= 25) break;
  }
  return checked > 0 && ok * 10 >= checked * 6;
}

/// "N45.4", "n 45.4" - a hemisphere letter in front of a number.
final RegExp _leadingHemisphere = RegExp(r'^([NSEWnsew])\s*(?=[-+\d.])');

/// "93.76W", "45°25'46.9\"N", "93.76 w." - a hemisphere letter at the end.
final RegExp _trailingHemisphere = RegExp(r'''(?<=[\d.°'"\s])([NSEWnsew])\.?$''');

/// "45d25m..." - degrees/minutes written with letters.
final RegExp _dmsLetters = RegExp(r'\d\s*[dD]\s*\d');

/// Parses one coordinate: decimal degrees ("45.4297", "-93,76" with decimal
/// comma), hemisphere letters ("93.76 W", "N45.43") and degrees/minutes/
/// seconds ("45°25'46.9\"N", "45 25 46.9", "45d25m46.9s").
/// Returns null when the text is not a finite coordinate.
double? parseCoordinateValue(String raw) {
  var s = raw.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1).trim();
  }
  if (s.isEmpty) return null;

  s = s
      .replaceAll('\u2212', '-') // minus sign
      .replaceAll('\u2032', "'") // prime
      .replaceAll('\u2019', "'")
      .replaceAll('\u2033', '"') // double prime
      .replaceAll('\u201D', '"')
      .replaceAll('\u00BA', '°') // masculine ordinal used as degree
      .replaceAll('\u02DA', '°');

  // "45d25m46.9s" style: turn the unit letters into symbols first so the
  // trailing "s" (seconds) is not mistaken for "South".
  if (_dmsLetters.hasMatch(s)) {
    s = s
        .replaceAllMapped(RegExp(r'(\d)\s*[dD](?=\s*\d)'), (m) => '${m[1]}°')
        .replaceAllMapped(RegExp(r'(\d)\s*[mM](?=\s*\d)'), (m) => "${m[1]}'")
        .replaceAllMapped(
            RegExp(r'(\d)\s*[sS](?=\s*[NSEWnsew]?\.?\s*$)'), (m) => '${m[1]}"');
  }

  int? hemisphereSign;
  final hemisphere =
      _leadingHemisphere.firstMatch(s) ?? _trailingHemisphere.firstMatch(s);
  if (hemisphere != null) {
    final letter = hemisphere.group(1)!.toUpperCase();
    hemisphereSign = (letter == 'S' || letter == 'W') ? -1 : 1;
    s = (s.substring(0, hemisphere.start) + s.substring(hemisphere.end)).trim();
    if (s.isEmpty) return null;
  }

  if (RegExp(r'^[+-]?\d+,\d+$').hasMatch(s)) {
    s = s.replaceFirst(',', '.');
  }

  double? value;
  final looksDms = s.contains('°') ||
      s.contains("'") ||
      s.contains('"') ||
      RegExp(r'^[+-]?\d+(\.\d+)?\s+\d').hasMatch(s) ||
      RegExp(r'^[+-]?\d+(\.\d+)?\s*[dD]\s*\d').hasMatch(s);
  if (looksDms) {
    final numbers = RegExp(r'\d+(?:[.,]\d+)?')
        .allMatches(s)
        .map((m) => double.parse(m.group(0)!.replaceAll(',', '.')))
        .toList();
    if (numbers.isEmpty || numbers.length > 3) return null;
    final degrees = numbers[0];
    final minutes = numbers.length > 1 ? numbers[1] : 0.0;
    final seconds = numbers.length > 2 ? numbers[2] : 0.0;
    if (minutes >= 60 || seconds >= 60) return null;
    value = degrees + minutes / 60 + seconds / 3600;
    if (s.startsWith('-')) value = -value;
  } else {
    value = double.tryParse(s);
  }

  if (value == null || !value.isFinite) return null;
  if (hemisphereSign != null) value = hemisphereSign * value.abs();
  return value;
}

/// Result of parsing a combined coordinate cell.
class CoordinatePair {
  const CoordinatePair(this.first, this.second, {this.isWkt = false});

  final double first;
  final double second;

  /// WKT `POINT(lon lat)` - always longitude first.
  final bool isWkt;
}

/// Parses "45.42, -93.76", "45.42 -93.76", "45.42;-93.76" or
/// "POINT(-93.76 45.42)" (WKT, longitude first).
CoordinatePair? parseCombinedCoordinate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final isWkt = RegExp(r'^\s*POINT\s*(Z|M|ZM)?\s*\(', caseSensitive: false).hasMatch(s);
  final numbers = RegExp(r'[-+]?\d+(?:\.\d+)?')
      .allMatches(s)
      .map((m) => double.tryParse(m.group(0)!))
      .whereType<double>()
      .toList();
  if (numbers.length < 2 || (!isWkt && numbers.length != 2)) return null;
  return CoordinatePair(numbers[0], numbers[1], isWkt: isWkt);
}

/// "99.99%", "0.87", "87,5" -> number; null when unreadable.
double? parseConfidence(String raw) {
  var s = raw.trim().replaceAll('%', '').trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^[+-]?\d+,\d+$').hasMatch(s)) s = s.replaceFirst(',', '.');
  final v = double.tryParse(s);
  return (v == null || !v.isFinite) ? null : v;
}

/// "5", "5.0" -> 5; null when unreadable.
int? parseCount(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final v = int.tryParse(s) ?? double.tryParse(s)?.round();
  return (v == null || v < 0) ? null : v;
}

/// "oak_wilt_results_20261002.csv" -> "oak_wilt_results_20261002".
String datasetNameFromFile(String fileName) {
  final name = fileName.split(RegExp(r'[\\/]')).last;
  final stripped = name.replaceAll(RegExp(r'\.(csv|tsv|txt)$', caseSensitive: false), '');
  return stripped.isEmpty ? 'Imported points' : stripped;
}
