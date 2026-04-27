import 'package:uuid/uuid.dart';

import '../models/dataset.dart';
import '../models/tree.dart';
import '../utils/geojson_validator.dart';

const _uuid = Uuid();

/// Result of parsing a GeoJSON file.
class GeoJSONParseResult {
  const GeoJSONParseResult({
    this.dataset,
    required this.trees,
    this.error,
  });

  final Dataset? dataset;
  final List<Tree> trees;
  final String? error;

  bool get success => error == null && dataset != null;
}

/// Parses GeoJSON FeatureCollection into Dataset and Tree list.
GeoJSONParseResult parseGeoJSON(
  Map<String, dynamic> json, {
  String? datasetName,
  String? diseaseType,
}) {
  if (!isValidGeoJSON(json)) {
    return GeoJSONParseResult(
      trees: [],
      error: 'Invalid GeoJSON: expected FeatureCollection with Point features',
    );
  }

  final features = json['features'] as List;
  final datasetId = _uuid.v4();
  final name = datasetName ?? 'Dataset ${DateTime.now().toIso8601String().substring(0, 10)}';
  final trees = <Tree>[];

  for (final f in features) {
    final feature = f as Map<String, dynamic>;
    final props = feature['properties'] as Map<String, dynamic>? ?? {};
    final geom = feature['geometry'] as Map<String, dynamic>;
    final coords = geom['coordinates'] as List;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();

    final filename = props['filename'] as String? ?? 'unknown';
    final treeId = _uuid.v4();

    String? predClass;
    if (props['predicted_class'] != null) {
      predClass = props['predicted_class'].toString();
    }

    double? score;
    if (props['prediction'] != null) {
      final s = props['prediction'].toString().replaceAll('%', '').trim();
      score = double.tryParse(s);
    }

    trees.add(Tree(
      id: treeId,
      datasetId: datasetId,
      filename: filename,
      latitude: lat,
      longitude: lon,
      imageS3Key: props['image_s3_key'] as String?,
      predictionScore: score,
      predictedClass: predClass,
      classification: props['classification'] as String?,
      description: props['description'] as String?,
    ));
  }

  final dataset = Dataset(
    id: datasetId,
    name: name,
    treeCount: trees.length,
    importedAt: DateTime.now(),
    diseaseType: diseaseType,
    enabled: true,
  );

  return GeoJSONParseResult(dataset: dataset, trees: trees);
}
