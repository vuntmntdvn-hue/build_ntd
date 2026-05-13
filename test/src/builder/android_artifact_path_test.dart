import 'dart:io';

import 'package:build_ntd/src/builder/android_artifact_path.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates an empty file at [path], making parent directories as needed.
void _touch(String path) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('');
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('artifact_path_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('findApkArtifact', () {
    test('locates the canonical APK without a flavor', () {
      final expected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-release.apk',
      );
      _touch(expected);

      final found = findApkArtifact(root.path, mode: 'release');

      expect(found, isNotNull);
      expect(p.equals(found!.path, expected), isTrue);
    });

    test('locates the flavored APK', () {
      final expected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'flutter-apk',
        'app-dev-release.apk',
      );
      _touch(expected);

      final found =
          findApkArtifact(root.path, mode: 'release', flavor: 'dev');

      expect(found, isNotNull);
      expect(p.equals(found!.path, expected), isTrue);
    });

    test('returns null when no APK exists', () {
      expect(findApkArtifact(root.path, mode: 'release'), isNull);
    });
  });

}
