import 'dart:io';

import 'package:build_ntd/src/builder/apk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Project {
  _Project(this.root);
  final Directory root;
  String get path => root.path;
  void delete() => root.deleteSync(recursive: true);

  void writePubspec(String contents) {
    File(p.join(path, 'pubspec.yaml')).writeAsStringSync(contents);
  }

  /// Creates an empty `.apk` at [relativePath] with optional mtime override.
  File touchApk(String relativePath, {DateTime? mtime}) {
    final f = File(p.join(path, relativePath));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('');
    if (mtime != null) f.setLastModifiedSync(mtime);
    return f;
  }
}

_Project _newProject() =>
    _Project(Directory.systemTemp.createTempSync('apk_locator_'));

void main() {
  late _Project project;

  setUp(() => project = _newProject());
  tearDown(() => project.delete());

  group('apkSearchDirs', () {
    test('returns project root + flutter default when no pubspec config', () {
      project.writePubspec('name: example\n');

      final dirs = apkSearchDirs(project.path);

      expect(dirs.length, 2);
      expect(dirs.first, project.path);
      expect(
        dirs.last,
        p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
      );
    });

    test('includes pubspec output_dir between root and flutter default', () {
      project.writePubspec('''
name: example
build_ntd:
  app_id: "001"
  app_name: smoke
  output_dir: ./dist
''');

      final dirs = apkSearchDirs(project.path);

      expect(dirs.length, 3);
      expect(dirs[0], project.path);
      expect(dirs[1], p.join(project.path, 'dist'));
      expect(
        dirs[2],
        p.join(project.path, 'build', 'app', 'outputs', 'flutter-apk'),
      );
    });

    test('handles missing pubspec gracefully (no throw)', () {
      // No pubspec.yaml written.
      final dirs = apkSearchDirs(project.path);
      expect(dirs.length, 2);
    });
  });

  group('findApkByName', () {
    test('finds a basename in the first search dir', () {
      final f = project.touchApk('App.apk');
      final found = findApkByName('App.apk', [project.path]);
      expect(found?.path, f.path);
    });

    test('finds a basename in a later search dir', () {
      project.touchApk('dist/App.apk');
      final found = findApkByName(
        'App.apk',
        [project.path, p.join(project.path, 'dist')],
      );
      expect(found?.path, p.join(project.path, 'dist', 'App.apk'));
    });

    test('returns the first match in search order, not necessarily newer', () {
      project
        ..touchApk('App.apk', mtime: DateTime(2020))
        ..touchApk(p.join('dist', 'App.apk'), mtime: DateTime(2026));

      final found = findApkByName(
        'App.apk',
        [project.path, p.join(project.path, 'dist')],
      );
      // First dir wins even though dist/ has a newer copy.
      expect(found?.path, p.join(project.path, 'App.apk'));
    });

    test('returns null when nothing matches', () {
      expect(findApkByName('missing.apk', [project.path]), isNull);
    });

    test('uses verbatim path when arg contains a separator', () {
      final relPath = p.join('sub', 'inner.apk');
      final f = project.touchApk(relPath);
      final found = findApkByName(
        // Testing that a path with separator is taken as-is rather than
        // fanning out across searchDirs (passed empty).
        p.join(project.path, relPath),
        const [],
      );
      // Use `p.equals` since File preserves the exact string the caller
      // passed in, which may differ in separator style.
      expect(p.equals(found!.path, f.path), isTrue);
    });

    test('returns null for non-existent absolute path', () {
      final missing = p.join(project.path, 'nowhere', 'ghost.apk');
      expect(findApkByName(missing, const []), isNull);
    });
  });

  group('findLatestApk', () {
    test('returns the most recently modified apk in a single dir', () {
      project
        ..touchApk('old.apk', mtime: DateTime(2024))
        ..touchApk('new.apk', mtime: DateTime(2026));

      final found = findLatestApk([project.path]);
      expect(found?.path, p.join(project.path, 'new.apk'));
    });

    test('compares mtimes across multiple dirs', () {
      project
        ..touchApk('old_root.apk', mtime: DateTime(2024))
        ..touchApk('dist/newer_dist.apk', mtime: DateTime(2026));

      final found = findLatestApk(
        [project.path, p.join(project.path, 'dist')],
      );
      expect(
        found?.path,
        p.join(project.path, 'dist', 'newer_dist.apk'),
      );
    });

    test('ignores non-apk files', () {
      project
        ..touchApk('shipped.aab', mtime: DateTime(2026))
        ..touchApk('older.apk', mtime: DateTime(2024));

      final found = findLatestApk([project.path]);
      expect(found?.path, p.join(project.path, 'older.apk'));
    });

    test('returns null when no .apk files exist anywhere', () {
      project.touchApk('notes.txt');
      expect(findLatestApk([project.path]), isNull);
    });

    test('skips missing directories silently', () {
      final missing = p.join(project.path, 'does_not_exist');
      project.touchApk('App.apk', mtime: DateTime(2026));
      final found = findLatestApk([project.path, missing]);
      expect(found?.path, p.join(project.path, 'App.apk'));
    });
  });

  group('apkCandidatePaths', () {
    test('returns the verbatim path for a path with separator', () {
      final givenPath = p.join('sub', 'inner.apk');
      expect(
        apkCandidatePaths(givenPath, [project.path]),
        [givenPath],
      );
    });

    test('lists joined candidates for a bare basename', () {
      final dirs = [project.path, p.join(project.path, 'dist')];
      expect(
        apkCandidatePaths('App.apk', dirs),
        [
          p.join(project.path, 'App.apk'),
          p.join(project.path, 'dist', 'App.apk'),
        ],
      );
    });
  });
}
