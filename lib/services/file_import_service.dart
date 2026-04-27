import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Result of picking and parsing a file.
class FileImportResult {
  const FileImportResult({
    this.json,
    this.error,
  });

  final Map<String, dynamic>? json;
  final String? error;

  bool get success => error == null && json != null;
}

/// Result of picking and reading a CSV file.
class CsvImportResult {
  const CsvImportResult({
    this.content,
    this.fileName,
    this.error,
  });

  final String? content;
  final String? fileName;
  final String? error;

  bool get success => error == null && content != null;
}

/// Pick a GeoJSON file and return parsed JSON.
Future<FileImportResult> pickAndReadGeoJSON() async {
  // Use FileType.any on Android to work around MIME type issues with .geojson
  // The file extension will be validated after selection
  final result = await FilePicker.pickFiles(
    type: Platform.isAndroid ? FileType.any : FileType.custom,
    allowedExtensions: Platform.isAndroid ? null : ['json', 'geojson'],
    withData: true,
  );

  if (result == null || result.files.isEmpty) {
    return const FileImportResult(error: 'No file selected');
  }

  final file = result.files.first;
  
  // Validate file extension (especially important when allowing any file type)
  final fileName = file.name.toLowerCase();
  if (!fileName.endsWith('.json') && !fileName.endsWith('.geojson')) {
    return FileImportResult(
      error: 'Please select a .json or .geojson file (selected: ${file.name})',
    );
  }
  
  if (file.bytes == null && file.path == null) {
    return const FileImportResult(error: 'Could not read file');
  }

  String content;
  if (file.bytes != null) {
    content = utf8.decode(file.bytes!);
  } else {
    try {
      content = await File(file.path!).readAsString();
    } catch (e) {
      return FileImportResult(error: 'Read error: $e');
    }
  }

  try {
    final json = jsonDecode(content) as Map<String, dynamic>;
    return FileImportResult(json: json);
  } catch (e) {
    return FileImportResult(error: 'Invalid JSON: $e');
  }
}

/// Pick a CSV file and return text content.
Future<CsvImportResult> pickAndReadCSV() async {
  final result = await FilePicker.pickFiles(
    type: Platform.isAndroid ? FileType.any : FileType.custom,
    allowedExtensions: Platform.isAndroid ? null : ['csv'],
    withData: true,
  );

  if (result == null || result.files.isEmpty) {
    return const CsvImportResult(error: 'No file selected');
  }

  final file = result.files.first;
  final fileName = file.name.toLowerCase();
  if (!fileName.endsWith('.csv')) {
    return CsvImportResult(
      error: 'Please select a .csv file (selected: ${file.name})',
    );
  }

  if (file.bytes == null && file.path == null) {
    return const CsvImportResult(error: 'Could not read file');
  }

  String content;
  if (file.bytes != null) {
    content = utf8.decode(file.bytes!);
  } else {
    try {
      content = await File(file.path!).readAsString();
    } catch (e) {
      return CsvImportResult(error: 'Read error: $e');
    }
  }

  return CsvImportResult(content: content, fileName: file.name);
}
