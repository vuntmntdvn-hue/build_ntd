import 'dart:io';

import 'package:build_ntd/src/builder/version_code_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

  String readGradle({bool kotlin = false}) => File(
    p.join(
      path,
      'android',
      'app',
      kotlin ? 'build.gradle.kts' : 'build.gradle',
    ),
  ).readAsStringSync();

  String readPubspec() =>
      File(p.join(path, 'pubspec.yaml')).readAsStringSync();

  void delete() => root.deleteSync(recursive: true);
}

_Project _newProject() =>
    _Project(Directory.systemTemp.createTempSync('version_code_'));

void main() {
  late _Project project;

  setUp(() => project = _newProject());
  tearDown(() => project.delete());

  group('bumpVersionCode (no explicit)', () {
    test('increments a Groovy literal by 1', () {
      project.writeGradle('''
android {
    defaultConfig {
        versionCode 5
        versionName "1.0.0"
    }
}
''');

      final result = bumpVersionCode(project.path);

      expect(result.oldValue, 5);
      expect(result.newValue, 6);
      expect(project.readGradle(), contains('versionCode 6'));
      // Unrelated lines untouched.
      expect(project.readGradle(), contains('versionName "1.0.0"'));
    });

    test('increments a Groovy `=` literal and preserves the assignment style',
        () {
      project.writeGradle('''
android {
    defaultConfig {
        versionCode = 7
    }
}
''');

      bumpVersionCode(project.path);

      expect(project.readGradle(), contains('versionCode = 8'));
    });

    test('increments a Kotlin DSL `=` literal in build.gradle.kts', () {
      project.writeGradle(
        '''
android {
    defaultConfig {
        versionCode = 11
    }
}
''',
        kotlin: true,
      );

      bumpVersionCode(project.path);

      expect(
        project.readGradle(kotlin: true),
        contains('versionCode = 12'),
      );
    });

    test(
      'preserves gradle dynamic ref and updates pubspec only',
      () {
        project
          ..writePubspec('name: example\nversion: 1.0.0+5\n')
          ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
        versionName flutterVersionName
    }
}
''');

        final result = bumpVersionCode(project.path);

        expect(result.oldValue, 5);
        expect(result.newValue, 6);

        // Gradle dynamic ref is intentionally untouched — it'll resolve
        // through the new pubspec value at build time.
        final gradle = project.readGradle();
        expect(gradle, contains('versionCode flutterVersionCode.toInteger()'));
        expect(gradle, contains('versionName flutterVersionName'));

        // pubspec carries the bumped value.
        expect(project.readPubspec(), contains('version: 1.0.0+6'));
        expect(result.filesUpdated.single, contains('pubspec.yaml'));
      },
    );

    test('updates both gradle and pubspec when both have a value', () {
      project
        ..writePubspec('name: example\nversion: 2.3.4+10\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 10
    }
}
''');

      final result = bumpVersionCode(project.path);

      expect(result.filesUpdated, hasLength(2));
      expect(project.readGradle(), contains('versionCode 11'));
      expect(project.readPubspec(), contains('version: 2.3.4+11'));
    });

    test('appends +N when pubspec version has no build number', () {
      project
        ..writePubspec('name: example\nversion: 1.0.0\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
    }
}
''');

      bumpVersionCode(project.path);

      expect(project.readPubspec(), contains('version: 1.0.0+6'));
    });

    test(
      'defaults pubspec build number to 1 when bumping from a dynamic ref',
      () {
        // Gradle has a dynamic ref (no literal), pubspec has `version:` but
        // no `+N`. The read should default to 1 (matching GradleVersionInfo),
        // and bump should produce `version: 1.0.0+2`.
        project
          ..writePubspec('name: example\nversion: 1.0.0\n')
          ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
    }
}
''');

        final result = bumpVersionCode(project.path);

        expect(result.oldValue, 1);
        expect(result.newValue, 2);
        expect(project.readPubspec(), contains('version: 1.0.0+2'));
        expect(
          project.readGradle(),
          contains('versionCode flutterVersionCode.toInteger()'),
        );
      },
    );

    test('does not touch pubspec when it has no `version:` field', () {
      project
        ..writePubspec('name: example\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
    }
}
''');

      final result = bumpVersionCode(project.path);

      expect(result.filesUpdated, hasLength(1));
      expect(result.filesUpdated.single, contains('build.gradle'));
    });

    test(
      'throws when both gradle and pubspec lack a determinable value',
      () {
        project
          ..writePubspec('name: example\n')
          ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
    }
}
''');

        expect(
          () => bumpVersionCode(project.path),
          throwsA(
            isA<VersionCodeException>().having(
              (e) => e.message,
              'message',
              contains('Cannot determine current versionCode'),
            ),
          ),
        );
      },
    );
  });

  group('bumpVersionCode (explicit)', () {
    test('sets the gradle literal to the given value', () {
      project.writeGradle('''
android {
    defaultConfig {
        versionCode 5
    }
}
''');

      final result = bumpVersionCode(project.path, explicit: 42);

      expect(result.newValue, 42);
      expect(project.readGradle(), contains('versionCode 42'));
    });

    test('updates pubspec even when explicit value is supplied', () {
      project
        ..writePubspec('name: example\nversion: 1.0.0+5\n')
        ..writeGradle('''
android {
    defaultConfig {
        versionCode 5
    }
}
''');

      bumpVersionCode(project.path, explicit: 100);

      expect(project.readGradle(), contains('versionCode 100'));
      expect(project.readPubspec(), contains('version: 1.0.0+100'));
    });

    test(
      'errors even with an explicit value when no writable target exists',
      () {
        // Gradle uses a dynamic ref (no literal to update) and pubspec has
        // no `version:` field — there's nowhere to write the new value.
        project
          ..writePubspec('name: example\n')
          ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
    }
}
''');

        expect(
          () => bumpVersionCode(project.path, explicit: 5),
          throwsA(
            isA<VersionCodeException>().having(
              (e) => e.message,
              'message',
              contains('Nothing to update'),
            ),
          ),
        );
      },
    );

    test(
      'writes into pubspec version even with no +N when explicit is given',
      () {
        project
          ..writePubspec('name: example\nversion: 1.0.0\n')
          ..writeGradle('''
android {
    defaultConfig {
        versionCode flutterVersionCode.toInteger()
    }
}
''');

        final result = bumpVersionCode(project.path, explicit: 42);

        expect(result.newValue, 42);
        // Gradle dynamic ref is left alone.
        expect(
          project.readGradle(),
          contains('versionCode flutterVersionCode.toInteger()'),
        );
        // pubspec gets `+42` appended.
        expect(project.readPubspec(), contains('version: 1.0.0+42'));
      },
    );

    test('rejects zero and negative values', () {
      project.writeGradle('android { defaultConfig { versionCode 1 } }');

      expect(
        () => bumpVersionCode(project.path, explicit: 0),
        throwsA(isA<VersionCodeException>()),
      );
      expect(
        () => bumpVersionCode(project.path, explicit: -3),
        throwsA(isA<VersionCodeException>()),
      );
    });
  });

  group('bumpVersionCode (errors)', () {
    test('throws when no gradle file exists', () {
      expect(
        () => bumpVersionCode(project.path),
        throwsA(
          isA<VersionCodeException>().having(
            (e) => e.message,
            'message',
            contains('build.gradle'),
          ),
        ),
      );
    });
  });

  group('bumpVersionCode (file preservation)', () {
    test('preserves comments, indentation, and unrelated lines', () {
      const original = '''
// some header comment

android {
    namespace "com.example"
    defaultConfig {
        applicationId "com.example"
        versionCode 5
        versionName "1.0.0"
        minSdkVersion 21
    }
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
''';
      project.writeGradle(original);

      bumpVersionCode(project.path);

      final updated = project.readGradle();
      // Every line except the versionCode line must round-trip unchanged.
      final originalLines = original.split('\n');
      final updatedLines = updated.split('\n');
      expect(updatedLines, hasLength(originalLines.length));
      for (var i = 0; i < originalLines.length; i++) {
        if (originalLines[i].contains('versionCode')) {
          expect(updatedLines[i], contains('versionCode 6'));
        } else {
          expect(updatedLines[i], originalLines[i]);
        }
      }
    });

    test('only changes the first versionCode line (flavor overrides skipped)',
        () {
      project.writeGradle('''
android {
    defaultConfig {
        versionCode 5
    }
    productFlavors {
        legacy {
            versionCode 999
        }
    }
}
''');

      bumpVersionCode(project.path);

      final updated = project.readGradle();
      expect(updated, contains('versionCode 6'));
      // Flavor override is left alone.
      expect(updated, contains('versionCode 999'));
    });
  });
}
