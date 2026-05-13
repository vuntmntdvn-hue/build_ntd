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

  group('findAabArtifact', () {
    test('locates the canonical AAB under the mode-named folder', () {
      final expected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'app-release.aab',
      );
      _touch(expected);

      final found = findAabArtifact(root.path, mode: 'release');

      expect(found, isNotNull);
      expect(p.equals(found!.path, expected), isTrue);
    });

    test('locates the flavored AAB under {flavor}{Mode}/', () {
      // Gradle camelCases the folder name when a flavor is present.
      final expected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'devRelease',
        'app-dev-release.aab',
      );
      _touch(expected);

      final found =
          findAabArtifact(root.path, mode: 'release', flavor: 'dev');

      expect(found, isNotNull);
      expect(p.equals(found!.path, expected), isTrue);
    });

    test('handles debug mode folder naming', () {
      final expected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'proDebug',
        'app-pro-debug.aab',
      );
      _touch(expected);

      final found = findAabArtifact(root.path, mode: 'debug', flavor: 'pro');

      expect(found, isNotNull);
      expect(p.equals(found!.path, expected), isTrue);
    });

    test('returns null when no AAB exists', () {
      expect(findAabArtifact(root.path, mode: 'release'), isNull);
    });

    test('falls back to a single non-canonical AAB in the bundle dir', () {
      // Edge case: Flutter sometimes drops a single oddly-named file. As long
      // as there's exactly one `.aab` in the expected directory, return it.
      final unexpected = p.join(
        root.path,
        'build',
        'app',
        'outputs',
        'bundle',
        'release',
        'something-weird.aab',
      );
      _touch(unexpected);

      final found = findAabArtifact(root.path, mode: 'release');

      expect(found, isNotNull);
      expect(p.equals(found!.path, unexpected), isTrue);
    });
  });
}
