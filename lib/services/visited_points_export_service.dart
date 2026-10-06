import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tree.dart';

/// Header of the visited export. The `type` column tells points and clusters
/// apart, so the file can be imported back: point rows on Home, cluster rows
/// on the map in cluster view.
const String visitedCsvHeader =
    'type,filename,latitude,longitude,visited_at,run,classification,'
    'confidence,count,members,notes';

/// CSV of the visited points and visited clusters of one run.
String buildVisitedCsv({
  required String runName,
  required Iterable<Tree> points,
  Iterable<Tree> clusters = const [],
}) {
  final buffer = StringBuffer()..writeln(visitedCsvHeader);
  for (final t in [...points, ...clusters]) {
    final isCluster = t.isCluster;
    buffer.writeln([
      isCluster ? 'cluster' : 'point',
      _csv(t.filename),
      t.latitude.toStringAsFixed(7),
      t.longitude.toStringAsFixed(7),
      _csv(t.visitedAt?.toIso8601String() ?? ''),
      _csv(runName),
      _csv(t.classification ?? ''),
      // Clusters never carry a confidence score.
      isCluster ? '' : (t.predictionScore?.toString() ?? ''),
      isCluster ? '${t.memberCount ?? ''}' : '',
      isCluster ? _csv(t.members.join('; ')) : '',
      _csv(t.visitNotes ?? ''),
    ].join(','));
  }
  return buffer.toString();
}

String _csv(String value) {
  if (value.contains(RegExp(r'[",\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

String _safeFileName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

/// "visited_<run>_<time>.csv"
String visitedFileName(String runName) =>
    'visited_${_safeFileName(runName)}_${_stamp(DateTime.now())}.csv';

/// "clusters_<run>_<time>.csv"
String clustersFileName(String runName) =>
    'clusters_${_safeFileName(runName)}_${_stamp(DateTime.now())}.csv';

/// Opens Android's "save" dialog (pick a folder, then Save) and writes [csv]
/// there. Returns false when the user cancelled.
Future<bool> saveCsvToDevice({
  required String fileName,
  required String csv,
  String dialogTitle = 'Save CSV',
}) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(csv)),
    mimeType: 'text/csv',
    dialogTitle: dialogTitle,
  );
  return uri != null;
}

/// Writes the CSV to a temp file and opens the system share sheet
/// (Drive, e-mail, messaging, ...).
Future<void> shareVisitedCsv({
  required String runName,
  required List<Tree> points,
  List<Tree> clusters = const [],
}) async {
  final csv = buildVisitedCsv(runName: runName, points: points, clusters: clusters);
  final dir = await getTemporaryDirectory();
  final name = visitedFileName(runName);
  final file = File(p.join(dir.path, name));
  await file.writeAsString(csv, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'Visited: $runName',
    ),
  );
}
