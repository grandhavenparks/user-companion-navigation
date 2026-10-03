import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A single imported point (usually one flagged tree / photo location).
///
/// Points are not coloured by health class; [classification] and
/// [predictionScore] are kept for display and export only.
@immutable
class Tree {
  const Tree({
    required this.id,
    required this.datasetId,
    required this.filename,
    required this.latitude,
    required this.longitude,
    this.imageS3Key,
    this.predictionScore,
    this.predictedClass,
    this.classification,
    this.description,
    this.visited = false,
    this.visitedAt,
    this.visitNotes,
  });

  final String id;
  final String datasetId;

  /// Name shown in the app: the image file name or a generated "Point N".
  final String filename;
  final double latitude;
  final double longitude;
  final String? imageS3Key;

  /// Model confidence as imported (either 0-1 or 0-100).
  final double? predictionScore;
  final String? predictedClass;
  final String? classification;
  final String? description;
  final bool visited;
  final DateTime? visitedAt;
  final String? visitNotes;

  LatLng get position => LatLng(latitude, longitude);

  /// Confidence formatted as a percentage, or null when unknown.
  String? get confidenceLabel {
    final score = predictionScore;
    if (score == null) return null;
    final percent = score <= 1.0 ? score * 100 : score;
    return '${percent.toStringAsFixed(1)}%';
  }

  Tree copyWith({
    bool? visited,
    DateTime? visitedAt,
  }) {
    return Tree(
      id: id,
      datasetId: datasetId,
      filename: filename,
      latitude: latitude,
      longitude: longitude,
      imageS3Key: imageS3Key,
      predictionScore: predictionScore,
      predictedClass: predictedClass,
      classification: classification,
      description: description,
      visited: visited ?? this.visited,
      visitedAt: visitedAt ?? this.visitedAt,
      visitNotes: visitNotes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dataset_id': datasetId,
      'filename': filename,
      'latitude': latitude,
      'longitude': longitude,
      'image_s3_key': imageS3Key,
      'prediction_score': predictionScore,
      'predicted_class': predictedClass,
      'classification': classification,
      'description': description,
      'visited': visited ? 1 : 0,
      'visited_at': visitedAt?.toIso8601String(),
      'visit_notes': visitNotes,
    };
  }

  factory Tree.fromMap(Map<String, dynamic> map) {
    return Tree(
      id: map['id'] as String,
      datasetId: map['dataset_id'] as String,
      filename: map['filename'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      imageS3Key: map['image_s3_key'] as String?,
      predictionScore: (map['prediction_score'] as num?)?.toDouble(),
      predictedClass: map['predicted_class'] as String?,
      classification: map['classification'] as String?,
      description: map['description'] as String?,
      visited: (map['visited'] as int?) == 1,
      visitedAt: map['visited_at'] != null
          ? DateTime.tryParse(map['visited_at'] as String)
          : null,
      visitNotes: map['visit_notes'] as String?,
    );
  }
}
