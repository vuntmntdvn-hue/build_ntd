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

  void writeGradle(String contents) {
    final dir = Directory(p.join(path, 'android', 'app'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'build.gradle')).writeAsStringSync(contents);
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
    expect(result.sectionAppended, isTrue);
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

  test(
    'returns sectionAppended=false and leaves file intact when section exists',
    () {
      const existing = '''
name: example
build_ntd:
  app_id: "999"
  app_name: existing
''';
      project.writePubspec(existing);

      final result = writeBuildNtdSample(project.path);

      expect(result.sectionAppended, isFalse);
      expect(result.appNameUsed, 'existing');
      expect(project.readPubspec(), existing);
    },
  );

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

  group('previewOutputNames', () {
    test('uses values from an existing build_ntd: block plus gradle', () {
      project
        ..writePubspec('''
name: example
version: 1.0.0+5
build_ntd:
  app_id: "780"
  app_name: Muslim
''')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
        versionName "1.0.0"
    }
}
''');

      final preview = previewOutputNames(project.path);

      expect(preview, isNotNull);
      // appId/appname taken straight from the block; versionName/Code from
      // gradle. We don't pin the date/time portion — those move with the
      // clock — so match on the stable surrounding segments.
      expect(preview!.apk, startsWith('App780_Muslim_v1.0.0(5)_'));
      expect(preview.apk, endsWith('_release.apk'));
      expect(preview.bundle, startsWith('App780_Muslim_v1.0.0(5)_'));
      expect(preview.bundle, endsWith('_release.aab'));
    });

    test('uses values just written when the block was missing', () {
      project.writePubspec('name: muslim_app\nversion: 2.3.4+9\n');

      writeBuildNtdSample(project.path);
      // No gradle file — version should fall back to pubspec's value.
      final preview = previewOutputNames(project.path);

      expect(preview, isNotNull);
      expect(preview!.apk, startsWith('App001_muslim_app_v2.3.4(9)_'));
      expect(preview.apk, endsWith('_release.apk'));
    });

    test('uses placeholders when version info is unavailable', () {
      project.writePubspec('''
name: example
build_ntd:
  app_id: "780"
  app_name: Muslim
''');
      // No gradle, no `version:` — versionName/Code can't be read.

      final preview = previewOutputNames(project.path);

      expect(preview, isNotNull);
      expect(preview!.apk, contains('v<x.y.z>(<N>)'));
    });

    test('honors a custom output_name template and swaps extension', () {
      project
        ..writePubspec(r'''
name: example
version: 1.0.0+5
build_ntd:
  app_id: "780"
  app_name: Muslim
  output_name: "App${appId}_${appname}.apk"
''')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
        versionName "1.0.0"
    }
}
''');

      final preview = previewOutputNames(project.path)!;

      expect(preview.apk, 'App780_Muslim.apk');
      expect(preview.bundle, 'App780_Muslim.aab');
    });

    test('returns null when the build_ntd block is missing/incomplete', () {
      project.writePubspec('name: example\n');

      // No block at all → BuildConfig.load throws → preview returns null.
      expect(previewOutputNames(project.path), isNull);
    });

    test('drops empty flavor cleanly (no double underscore)', () {
      project
        ..writePubspec('''
name: example
version: 1.0.0+5
build_ntd:
  app_id: "780"
  app_name: Muslim
''')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
        versionName "1.0.0"
    }
}
''');

      final preview = previewOutputNames(project.path)!;

      expect(preview.apk, isNot(contains('__')));
    });
  });
}
