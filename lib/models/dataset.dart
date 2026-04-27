import 'package:flutter/foundation.dart';

/// An imported GeoJSON dataset (collection of trees).
@immutable
class Dataset {
  const Dataset({
    required this.id,
    required this.name,
    required this.treeCount,
    this.importedAt,
    this.diseaseType,
    this.enabled = true,
  });

  final String id;
  final String name;
  final int treeCount;
  final DateTime? importedAt;
  final String? diseaseType;
  final bool enabled;

  Dataset copyWith({
    String? id,
    String? name,
    int? treeCount,
    DateTime? importedAt,
    String? diseaseType,
    bool? enabled,
  }) {
    return Dataset(
      id: id ?? this.id,
      name: name ?? this.name,
      treeCount: treeCount ?? this.treeCount,
      importedAt: importedAt ?? this.importedAt,
      diseaseType: diseaseType ?? this.diseaseType,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tree_count': treeCount,
      'imported_at': importedAt?.toIso8601String(),
      'disease_type': diseaseType,
      'enabled': enabled ? 1 : 0,
    };
  }

  factory Dataset.fromMap(Map<String, dynamic> map) {
    return Dataset(
      id: map['id'] as String,
      name: map['name'] as String,
      treeCount: map['tree_count'] as int,
      importedAt: map['imported_at'] != null
          ? DateTime.parse(map['imported_at'] as String)
          : null,
      diseaseType: map['disease_type'] as String?,
      enabled: (map['enabled'] as int?) != 0,
    );
  }
}
