import 'package:uuid/uuid.dart';

import '../models/dataset.dart';
import '../models/tree.dart';

class CsvPointsParseResult {
  const CsvPointsParseResult({
    this.dataset,
    this.trees,
    this.error,
  });

  final Dataset? dataset;
  final List<Tree>? trees;
  final String? error;

  bool get success => error == null && dataset != null && trees != null;
}

CsvPointsParseResult parsePointsCsv(
  String csvContent, {
  required String sourceName,
}) {
  final lines = csvContent
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length < 2) {
    return const CsvPointsParseResult(error: 'CSV must include header and rows');
  }

  final header = lines.first.split(',');
  final latIndex = _findColumn(header, const ['latitude', 'lat']);
  final lngIndex = _findColumn(header, const ['longitude', 'lng', 'lon', 'long']);
  if (latIndex == -1 || lngIndex == -1) {
    return const CsvPointsParseResult(
      error: 'CSV header must include Latitude and Longitude columns',
    );
  }

  const uuid = Uuid();
  final datasetId = uuid.v4();
  final trees = <Tree>[];

  for (int i = 1; i < lines.length; i++) {
    final parts = lines[i].split(',');
    if (parts.length <= latIndex || parts.length <= lngIndex) continue;
    try {
      final lat = double.parse(parts[latIndex].trim());
      final lng = double.parse(parts[lngIndex].trim());
      trees.add(
        Tree(
          id: uuid.v4(),
          datasetId: datasetId,
          filename: 'Point ${trees.length + 1}',
          latitude: lat,
          longitude: lng,
          predictedClass: 'sick',
        ),
      );
    } catch (_) {
      // Skip malformed rows.
    }
  }

  if (trees.isEmpty) {
    return const CsvPointsParseResult(error: 'No valid point rows found in CSV');
  }

  final datasetName =
      sourceName.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');

  final dataset = Dataset(
    id: datasetId,
    name: datasetName,
    treeCount: trees.length,
    importedAt: DateTime.now(),
  );

  return CsvPointsParseResult(dataset: dataset, trees: trees);
}

int _findColumn(List<String> header, List<String> names) {
  for (int i = 0; i < header.length; i++) {
    final normalized = header[i].trim().toLowerCase();
    if (names.contains(normalized)) return i;
  }
  return -1;
}
