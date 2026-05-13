import 'dart:io';

import 'package:build_ntd/src/builder/build_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Sets up a throw-away project directory under the system temp.
class _Project {
  _Project(this.root);

  final Directory root;
  String get path => root.path;

  void writePubspec(String contents) {
    File(p.join(path, 'pubspec.yaml')).writeAsStringSync(contents);
  }

  void writeGradle(String contents, {bool kotlin = false}) {
    final dir = Directory(p.join(path, 'android', 'app'))
      ..createSync(recursive: true);
    final filename = kotlin ? 'build.gradle.kts' : 'build.gradle';
    File(p.join(dir.path, filename)).writeAsStringSync(contents);
  }

  void delete() => root.deleteSync(recursive: true);
}

_Project _newProject() =>
    _Project(Directory.systemTemp.createTempSync('build_ntd_test_'));

void main() {
  group('BuildConfig.load', () {
    late _Project project;

    setUp(() => project = _newProject());
    tearDown(() => project.delete());

    test('reads app_id and app_name with no template override', () {
      project.writePubspec('''
name: example
build_ntd:
  app_id: 780
  app_name: Muslim
''');

      final cfg = BuildConfig.load(project.path);

      expect(cfg.appId, '780');
      expect(cfg.appName, 'Muslim');
      // Null signals "use the command's default template".
      expect(cfg.outputNameTemplate, isNull);
      expect(cfg.outputDir, isNull);
    });

    test('accepts string app_id and preserves overrides', () {
      project.writePubspec(r'''
name: example
build_ntd:
  app_id: "abc123"
  app_name: Muslim
  output_name: "${appname}.apk"
  output_dir: ./dist
''');

      final cfg = BuildConfig.load(project.path);

      expect(cfg.appId, 'abc123');
      expect(cfg.outputNameTemplate, r'${appname}.apk');
      expect(cfg.outputDir, './dist');
    });

    test('throws when pubspec.yaml is missing', () {
      expect(
        () => BuildConfig.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('pubspec.yaml not found'),
          ),
        ),
      );
    });

    test('throws when build_ntd section is missing', () {
      project.writePubspec('name: example\n');
      expect(
        () => BuildConfig.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('Missing `build_ntd:` section'),
          ),
        ),
      );
    });

    test('throws when app_id is missing', () {
      project.writePubspec('''
name: example
build_ntd:
  app_name: Muslim
''');
      expect(
        () => BuildConfig.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('Missing `app_id`'),
          ),
        ),
      );
    });

    test('throws when app_name is missing', () {
      project.writePubspec('''
name: example
build_ntd:
  app_id: 780
''');
      expect(
        () => BuildConfig.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('Missing `app_name`'),
          ),
        ),
      );
    });
  });

  group('GradleVersionInfo.load', () {
    late _Project project;

    setUp(() => project = _newProject());
    tearDown(() => project.delete());

    test('reads Groovy literal values (space-separated)', () {
      project
        ..writePubspec('name: example\n')
        ..writeGradle('''
android {
    defaultConfig {
        applicationId "com.example"
        versionCode 42
        versionName "2.3.4"
    }
}
''');

      final info = GradleVersionInfo.load(project.path);
      expect(info.versionName, '2.3.4');
      expect(info.versionCode, '42');
    });

    test('reads Groovy assignment-style values', () {
      project
        ..writePubspec('name: example\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode = 7
        versionName = "1.2.3"
    }
}
''');

      final info = GradleVersionInfo.load(project.path);
      expect(info.versionName, '1.2.3');
      expect(info.versionCode, '7');
    });

    test('reads Kotlin DSL values from build.gradle.kts', () {
      project
        ..writePubspec('name: example\n')
        ..writeGradle(
          '''
android {
    defaultConfig {
        versionCode = 9
        versionName = "5.6.7"
    }
}
''',
          kotlin: true,
        );

      final info = GradleVersionInfo.load(project.path);
      expect(info.versionName, '5.6.7');
      expect(info.versionCode, '9');
    });

    test('falls back to pubspec version when Gradle uses dynamic refs', () {
      project
        ..writePubspec('''
name: example
version: 9.8.7+123
''')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
''');

      final info = GradleVersionInfo.load(project.path);
      expect(info.versionName, '9.8.7');
      expect(info.versionCode, '123');
    });

    test('defaults build number to 1 when pubspec version omits "+n"', () {
      project
        ..writePubspec('''
name: example
version: 1.0.0
''')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
''');

      final info = GradleVersionInfo.load(project.path);
      expect(info.versionName, '1.0.0');
      expect(info.versionCode, '1');
    });

    test('throws when no Gradle file exists', () {
      project.writePubspec('name: example\n');
      expect(
        () => GradleVersionInfo.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('build.gradle'),
          ),
        ),
      );
    });

    test('throws when Gradle uses dynamic refs and pubspec has no version',
        () {
      project
        ..writePubspec('name: example\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
''');

      expect(
        () => GradleVersionInfo.load(project.path),
        throwsA(
          isA<BuildConfigException>().having(
            (e) => e.message,
            'message',
            contains('no `version:` is set'),
          ),
        ),
      );
    });
  });
}
