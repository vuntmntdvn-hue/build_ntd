import 'dart:io';

import 'package:build_ntd/src/builder/build_records.dart';
import 'package:build_ntd/src/builder/git_info.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Project {
  _Project(this.root);
  final Directory root;
  String get path => root.path;
  void delete() => root.deleteSync(recursive: true);
  File get records => File(p.join(path, buildRecordsFileName));
  String readRecords() => records.readAsStringSync();
}

_Project _newProject() =>
    _Project(Directory.systemTemp.createTempSync('build_records_'));

GitInfo _gitInfo({
  String shortSha = 'a1b2c3d',
  String fullSha = 'a1b2c3d4e5f6789012345678901234567890abcd',
  String? branch = 'main',
  bool isDirty = false,
}) =>
    GitInfo(
      shortSha: shortSha,
      fullSha: fullSha,
      branch: branch,
      isDirty: isDirty,
    );

void main() {
  late _Project project;

  setUp(() => project = _newProject());
  tearDown(() => project.delete());

  test('creates the file with header on first write', () {
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 14, 30),
        artifact: 'App780_Muslim_release.apk',
        git: _gitInfo(),
      ),
    );

    expect(project.records.existsSync(), isTrue);
    final content = project.readRecords();
    expect(content, contains('# build_ntd build records'));
    expect(content, contains('| When'));
    // Stable, narrow checks — full row would exceed the line-length limit.
    expect(content, contains('| 2026-05-13 14:30 |'));
    expect(content, contains('| App780_Muslim_release.apk |'));
    expect(content, contains('| a1b2c3d | main | clean |'));
  });

  test('appends to an existing file without re-writing the header', () {
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 14, 30),
        artifact: 'first.apk',
        git: _gitInfo(shortSha: 'aaaaaaa'),
      ),
    );
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 15, 45),
        artifact: 'second.apk',
        git: _gitInfo(shortSha: 'bbbbbbb', isDirty: true),
      ),
    );

    final content = project.readRecords();
    final headerCount = '# build_ntd build records'.allMatches(content).length;
    expect(headerCount, 1);
    expect(content, contains('| first.apk'));
    expect(content, contains('| aaaaaaa | main | clean |'));
    expect(content, contains('| second.apk'));
    expect(content, contains('| bbbbbbb | main | dirty |'));
  });

  test('renders em-dashes for every git column when no git info', () {
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 16),
        artifact: 'no_git.apk',
        git: null,
      ),
    );

    final content = project.readRecords();
    expect(content, contains('| no_git.apk | — | — | — |'));
  });

  test('renders branch=(detached) and status=detached when HEAD is detached',
      () {
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 16),
        artifact: 'detached.apk',
        git: _gitInfo(branch: null),
      ),
    );

    final content = project.readRecords();
    expect(content, contains('| a1b2c3d | (detached) | detached |'));
  });

  test('handles an existing file that does not end with a newline', () {
    // User manually edited the file and stripped the trailing newline.
    project.records.writeAsStringSync('# build_ntd build records\n'
        '\n'
        '| When | Artifact | Commit | Branch | Status |\n'
        '|------|----------|--------|--------|--------|\n'
        '| 2026-01-01 00:00 | old.apk | 0000000 | main | clean |');

    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 5, 13, 16),
        artifact: 'new.apk',
        git: _gitInfo(shortSha: 'fedcba9'),
      ),
    );

    final content = project.readRecords();
    // Old row still present, new row on its own line.
    expect(content, contains('| 2026-01-01 00:00 | old.apk'));
    expect(content, contains('| new.apk | fedcba9'));
    // No row got concatenated onto another.
    expect(content, isNot(contains('clean |2026-')));
  });

  test('pads single-digit month/day/hour/minute correctly', () {
    appendBuildRecord(
      project.path,
      BuildRecord(
        timestamp: DateTime(2026, 1, 7, 4, 9),
        artifact: 'padded.apk',
        git: _gitInfo(),
      ),
    );

    expect(project.readRecords(), contains('| 2026-01-07 04:09 |'));
  });
}
