import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tree.dart';

/// CSV with everything needed to find a visited point again. The file can be
/// imported back into the app (it has latitude/longitude columns).
String buildVisitedPointsCsv(
  Iterable<Tree> trees, {
  Map<String, String> datasetNames = const {},
}) {
  final buffer = StringBuffer()
    ..writeln('filename,latitude,longitude,visited_at,dataset,classification,confidence,notes');
  for (final t in trees) {
    buffer.writeln([
      _csv(t.filename),
      t.latitude.toStringAsFixed(7),
      t.longitude.toStringAsFixed(7),
      _csv(t.visitedAt?.toIso8601String() ?? ''),
      _csv(datasetNames[t.datasetId] ?? ''),
      _csv(t.classification ?? ''),
      t.predictionScore?.toString() ?? '',
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

/// Writes the CSV to a temp file and opens the system share sheet
/// (Save to Files, Drive, e-mail, ...).
Future<void> shareVisitedPointsCsv(
  List<Tree> visitedTrees, {
  Map<String, String> datasetNames = const {},
}) async {
  final csv = buildVisitedPointsCsv(visitedTrees, datasetNames: datasetNames);
  final dir = await getTemporaryDirectory();
  final name = 'visited_points_${_stamp(DateTime.now())}.csv';
  final file = File(p.join(dir.path, name));
  await file.writeAsString(csv, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: name)],
      subject: 'Visited points',
    ),
  );
}
