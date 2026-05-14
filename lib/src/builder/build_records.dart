import 'dart:io';

import 'package:build_ntd/src/builder/git_info.dart';
import 'package:path/path.dart' as p;

/// Filename of the records markdown at the project root.
const buildRecordsFileName = 'build_ntd_records.md';

/// Markdown header written when the records file is first created.
const _markdownHeader = '''
# build_ntd build records

| When             | Artifact | Commit | Branch | Status |
|------------------|----------|--------|--------|--------|
''';

/// One row appended to `build_ntd_records.md` per successful build.
class BuildRecord {
  BuildRecord({
    required this.timestamp,
    required this.artifact,
    required this.git,
  });

  final DateTime timestamp;

  /// Basename of the renamed artifact (e.g. `App780_..._release.apk`).
  final String artifact;

  /// Git context, or `null` when the project isn't a git repo.
  final GitInfo? git;
}

/// Appends a row to `build_ntd_records.md` at [projectRoot]. Creates the file
/// with a markdown header on the first call. Whole-file rewrite — small
/// enough to not matter, atomic enough to survive partial writes.
void appendBuildRecord(String projectRoot, BuildRecord record) {
  final file = File(p.join(projectRoot, buildRecordsFileName));
  final row = _renderRow(record);

  if (!file.existsSync()) {
    file.writeAsStringSync('$_markdownHeader$row\n');
    return;
  }

  var existing = file.readAsStringSync();
  if (!existing.endsWith('\n')) existing += '\n';
  file.writeAsStringSync('$existing$row\n');
}

String _renderRow(BuildRecord r) {
  final when = _formatTimestamp(r.timestamp);
  final commit = r.git?.shortSha ?? '—';
  final branch = r.git == null
      ? '—'
      : (r.git!.branch ?? '(detached)');
  final status = r.git == null ? '—' : r.git!.statusLabel;
  return '| $when | ${r.artifact} | $commit | $branch | $status |';
}

String _formatTimestamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
