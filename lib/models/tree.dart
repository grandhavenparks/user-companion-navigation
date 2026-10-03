import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A single navigable point: an imported point (usually one flagged tree /
/// photo location) or a cluster of points.
///
/// Points are not coloured by health class; [classification] and
/// [predictionScore] are kept for display and export only. Clusters have no
/// confidence score.
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
    this.memberCount,
    this.members = const [],
    this.parkId,
    this.areaIndex,
  });

  final String id;
  final String datasetId;

  /// Name shown in the app: the image file name, "Point N" or "Cluster N (k trees)".
  final String filename;
  final double latitude;
  final double longitude;
  final String? imageS3Key;

  /// Model confidence as imported (either 0-1 or 0-100). Always null for clusters.
  final double? predictionScore;
  final String? predictedClass;

  /// For clusters: the most common classification of the members.
  final String? classification;
  final String? description;
  final bool visited;
  final DateTime? visitedAt;
  final String? visitNotes;

  /// Number of points merged into this cluster; null for a normal point,
  /// 0 when an imported cluster file did not say.
  final int? memberCount;

  /// Names of the merged points (may be empty for imported cluster files).
  final List<String> members;

  /// For clusters: the park and area its members are in. Lets a cluster whose
  /// average position falls just outside the boundary still be navigated.
  final String? parkId;
  final int? areaIndex;

  bool get isCluster => memberCount != null;

  LatLng get position => LatLng(latitude, longitude);

  /// Confidence formatted as a percentage, or null when unknown (always null
  /// for clusters).
  String? get confidenceLabel {
    if (isCluster) return null;
    final score = predictionScore;
    if (score == null) return null;
    final percent = score <= 1.0 ? score * 100 : score;
    return '${percent.toStringAsFixed(1)}%';
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
      'member_count': memberCount,
      'members': members.isEmpty ? null : members.join('\n'),
      'park_id': parkId,
      'area_index': areaIndex,
    };
  }

  factory Tree.fromMap(Map<String, dynamic> map) {
    final membersText = map['members'] as String?;
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
      memberCount: (map['member_count'] as num?)?.toInt(),
      members: membersText == null || membersText.isEmpty
          ? const []
          : membersText.split('\n'),
      parkId: map['park_id'] as String?,
      areaIndex: (map['area_index'] as num?)?.toInt(),
    );
  }
}
