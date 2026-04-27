import 'package:flutter/foundation.dart';

/// Health classification from analysis.
enum TreeClassification {
  environment,
  sick,
  dead;

  static TreeClassification fromString(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('environment') || lower.contains('healthy')) {
      return TreeClassification.environment;
    }
    if (lower.contains('sick')) {
      return TreeClassification.sick;
    }
    if (lower.contains('dead')) {
      return TreeClassification.dead;
    }
    return TreeClassification.environment;
  }
}

/// A single tree/point from GeoJSON analysis results.
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
  final String filename;
  final double latitude;
  final double longitude;
  final String? imageS3Key;
  final double? predictionScore;
  final String? predictedClass;
  final String? classification;
  final String? description;
  final bool visited;
  final DateTime? visitedAt;
  final String? visitNotes; // User comments when visiting tree

  TreeClassification get treeClassification =>
      predictedClass != null
          ? TreeClassification.fromString(predictedClass!)
          : TreeClassification.environment;

  Tree copyWith({
    String? id,
    String? datasetId,
    String? filename,
    double? latitude,
    double? longitude,
    String? imageS3Key,
    double? predictionScore,
    String? predictedClass,
    String? classification,
    String? description,
    bool? visited,
    DateTime? visitedAt,
    String? visitNotes,
  }) {
    return Tree(
      id: id ?? this.id,
      datasetId: datasetId ?? this.datasetId,
      filename: filename ?? this.filename,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageS3Key: imageS3Key ?? this.imageS3Key,
      predictionScore: predictionScore ?? this.predictionScore,
      predictedClass: predictedClass ?? this.predictedClass,
      classification: classification ?? this.classification,
      description: description ?? this.description,
      visited: visited ?? this.visited,
      visitedAt: visitedAt ?? this.visitedAt,
      visitNotes: visitNotes ?? this.visitNotes,
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
      predictionScore: map['prediction_score'] != null
          ? (map['prediction_score'] as num).toDouble()
          : null,
      predictedClass: map['predicted_class'] as String?,
      classification: map['classification'] as String?,
      description: map['description'] as String?,
      visited: (map['visited'] as int?) == 1,
      visitedAt: map['visited_at'] != null
          ? DateTime.parse(map['visited_at'] as String)
          : null,
      visitNotes: map['visit_notes'] as String?,
    );
  }
  
  /// Check if this tree is infected (sick or dead)
  bool get isInfected =>
      treeClassification == TreeClassification.sick ||
      treeClassification == TreeClassification.dead;
}
