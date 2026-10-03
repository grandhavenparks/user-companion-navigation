import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file chosen by the user for import.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class FileImportException implements Exception {
  const FileImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _allowedExtensions = ['.csv', '.tsv', '.txt'];

/// Lets the user pick a CSV/TSV file. Returns null when cancelled.
///
/// `FileType.any` is used on purpose: Android file providers report CSV
/// files with many different MIME types, so filtering by type hides files.
Future<PickedFile?> pickPointsFile() async {
  final file = await FilePicker.pickFile(type: FileType.any);
  if (file == null) return null;

  final name = file.name;
  final lower = name.toLowerCase();
  final hasExtension = lower.contains('.');
  if (hasExtension && !_allowedExtensions.any(lower.endsWith)) {
    throw FileImportException(
        'Please choose a .csv file (selected: $name).');
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw FileImportException('$name is empty.');
  }
  return PickedFile(name: name, bytes: bytes);
}
