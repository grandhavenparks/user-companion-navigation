import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/tree.dart';

String buildVisitedPointsCsv(Iterable<Tree> trees) {
  final buf = StringBuffer('latitude,longitude\n');
  for (final t in trees) {
    buf.writeln('${t.latitude},${t.longitude}');
  }
  return buf.toString();
}

/// Writes CSV to a temp file and opens the system share sheet (Save to Files, Drive, etc.).
Future<void> shareVisitedPointsCsv(List<Tree> visitedTrees) async {
  final csv = buildVisitedPointsCsv(visitedTrees);
  final dir = await getTemporaryDirectory();
  final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final file = File('${dir.path}/visited_points_$stamp.csv');
  await file.writeAsString(csv);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv', name: 'visited_points_$stamp.csv')],
    subject: 'Visited points',
  );
}
