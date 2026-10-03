import 'package:flutter/foundation.dart';

/// A single visit/inspection record for a tree.
@immutable
class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.treeId,
    required this.visitedAt,
    this.notes,
    this.photoPaths = const [],
  });

  final String id;
  final String treeId;
  final DateTime visitedAt;
  final String? notes;
  final List<String> photoPaths;

  VisitRecord copyWith({
    String? id,
    String? treeId,
    DateTime? visitedAt,
    String? notes,
    List<String>? photoPaths,
  }) {
    return VisitRecord(
      id: id ?? this.id,
      treeId: treeId ?? this.treeId,
      visitedAt: visitedAt ?? this.visitedAt,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tree_id': treeId,
      'visited_at': visitedAt.toIso8601String(),
      'notes': notes,
      'photo_paths': photoPaths.join('|'),
    };
  }

  factory VisitRecord.fromMap(Map<String, dynamic> map) {
    final paths = map['photo_paths'] as String?;
    return VisitRecord(
      id: map['id'] as String,
      treeId: map['tree_id'] as String,
      visitedAt: DateTime.parse(map['visited_at'] as String),
      notes: map['notes'] as String?,
      photoPaths: paths != null && paths.isNotEmpty
          ? paths.split('|').toList()
          : [],
    );
  }
}
