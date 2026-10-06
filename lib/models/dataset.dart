import 'package:flutter/foundation.dart';

/// What a dataset holds.
enum DatasetKind {
  /// Points imported from a CSV (one field run).
  points,

  /// Clusters made from a run (created in the app or imported from a
  /// cluster CSV in cluster view). Belongs to the run in [Dataset.parentId].
  clusters;

  static DatasetKind fromName(String? name) =>
      name == 'clusters' ? DatasetKind.clusters : DatasetKind.points;
}

/// An imported CSV ("run") or a cluster set belonging to a run.
@immutable
class Dataset {
  const Dataset({
    required this.id,
    required this.name,
    required this.treeCount,
    this.importedAt,
    this.diseaseType,
    this.enabled = true,
    this.kind = DatasetKind.points,
    this.parentId,
  });

  final String id;
  final String name;

  /// Number of points (or clusters) in the dataset.
  final int treeCount;
  final DateTime? importedAt;
  final String? diseaseType;

  /// Legacy flag from 1.0/1.1; the app now uses one active run instead.
  final bool enabled;
  final DatasetKind kind;

  /// For cluster sets: id of the run they were made from.
  final String? parentId;

  bool get isRun => kind == DatasetKind.points;
  bool get isClusterSet => kind == DatasetKind.clusters;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tree_count': treeCount,
      'imported_at': importedAt?.toIso8601String(),
      'disease_type': diseaseType,
      'enabled': enabled ? 1 : 0,
      'kind': kind.name,
      'parent_id': parentId,
    };
  }

  factory Dataset.fromMap(Map<String, dynamic> map) {
    return Dataset(
      id: map['id'] as String,
      name: map['name'] as String,
      treeCount: (map['tree_count'] as num?)?.toInt() ?? 0,
      importedAt: map['imported_at'] != null
          ? DateTime.tryParse(map['imported_at'] as String)
          : null,
      diseaseType: map['disease_type'] as String?,
      enabled: (map['enabled'] as int?) != 0,
      kind: DatasetKind.fromName(map['kind'] as String?),
      parentId: map['parent_id'] as String?,
    );
  }
}
