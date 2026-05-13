import 'dart:io';

import 'package:build_ntd/src/builder/pubspec_sample.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

class _Project {
  _Project(this.root);

  final Directory root;
  String get path => root.path;

  void writePubspec(String contents) {
    File(p.join(path, 'pubspec.yaml')).writeAsStringSync(contents);
  }

  String readPubspec() =>
      File(p.join(path, 'pubspec.yaml')).readAsStringSync();

  void delete() => root.deleteSync(recursive: true);
}

_Project _newProject() =>
    _Project(Directory.systemTemp.createTempSync('pubspec_sample_'));

void main() {
  late _Project project;

  setUp(() => project = _newProject());
  tearDown(() => project.delete());

  test('appends a build_ntd: section to a minimal pubspec', () {
    project.writePubspec('name: example\nversion: 1.0.0+1\n');

    final result = writeBuildNtdSample(project.path);

    final updated = project.readPubspec();
    expect(updated, contains('build_ntd:'));
    expect(updated, contains('app_id: "001"'));
    expect(updated, contains('app_name: example'));
    expect(updated, contains('# output_name:'));
    expect(updated, contains('# output_dir: ./dist'));
    expect(result.pubspecPath, 'pubspec.yaml');
    expect(result.appNameUsed, 'example');
  });

  test('auto-fills app_name from the host pubspec `name:` field', () {
    project.writePubspec('name: muslim_app\nversion: 0.0.1\n');

    final result = writeBuildNtdSample(project.path);

    expect(result.appNameUsed, 'muslim_app');
    expect(project.readPubspec(), contains('app_name: muslim_app'));
  });

  test('falls back to `my_flutter_app` when pubspec has no `name:`', () {
    project.writePubspec('# nothing yet\n');

    final result = writeBuildNtdSample(project.path);

    expect(result.appNameUsed, 'my_flutter_app');
    expect(project.readPubspec(), contains('app_name: my_flutter_app'));
  });

  test('refuses when a build_ntd: section already exists', () {
    project.writePubspec('''
name: example
build_ntd:
  app_id: 999
  app_name: existing
''');

    expect(
      () => writeBuildNtdSample(project.path),
      throwsA(
        isA<PubspecSampleException>().having(
          (e) => e.message,
          'message',
          contains('already exists'),
        ),
      ),
    );
  });

  test('throws when pubspec.yaml is missing', () {
    expect(
      () => writeBuildNtdSample(project.path),
      throwsA(
        isA<PubspecSampleException>().having(
          (e) => e.message,
          'message',
          contains('not found'),
        ),
      ),
    );
  });

  test('preserves every line above the new section byte-identical', () {
    const original = '''
name: example
description: A demo app.
version: 1.2.3+4

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter
''';
    project.writePubspec(original);

    writeBuildNtdSample(project.path);

    final updated = project.readPubspec();
    // The original file (with its trailing newline) appears verbatim,
    // followed by a blank line and the new section.
    expect(updated, startsWith(original));
    expect(updated.substring(original.length), startsWith('\n#'));
  });

  test('normalizes trailing whitespace to a single newline', () {
    // Tab + spaces + multiple blank lines at the end — should all collapse.
    project.writePubspec('name: example\nversion: 1.0.0+1\n\n\n   \t\n');

    writeBuildNtdSample(project.path);

    final updated = project.readPubspec();
    // The file ends with exactly one `\n`.
    expect(updated.endsWith('\n'), isTrue);
    expect(updated.endsWith('\n\n'), isFalse);
  });

  test('the rendered pubspec parses as valid YAML', () {
    project.writePubspec('name: example\nversion: 1.0.0+1\n');

    writeBuildNtdSample(project.path);

    final doc = loadYaml(project.readPubspec());
    expect(doc, isA<YamlMap>());
    final section = (doc as YamlMap)['build_ntd'];
    expect(section, isA<YamlMap>());
    expect((section as YamlMap)['app_id'], '001');
    expect(section['app_name'], 'example');
  });

  test('appends a section to a completely empty pubspec', () {
    project.writePubspec('');

    final result = writeBuildNtdSample(project.path);

    expect(result.appNameUsed, 'my_flutter_app');
    final updated = project.readPubspec();
    // Starts straight with the section header — no leading blank line.
    expect(updated, startsWith('# Settings for the build_ntd CLI.'));
  });
}
