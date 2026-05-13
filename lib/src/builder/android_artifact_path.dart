import 'dart:io';

import 'package:path/path.dart' as p;

/// Locates the APK produced by `flutter build apk` for the given
/// [mode] (`release` / `debug` / `profile`) and optional [flavor].
///
/// Tries the canonical filename first, then falls back to "the single
/// `app*.apk` in the output dir" so quirks like custom suffixes still work.
File? findApkArtifact(
  String projectRoot, {
  required String mode,
  String? flavor,
}) {
  final apkDir = p.join(
    projectRoot,
    'build',
    'app',
    'outputs',
    'flutter-apk',
  );
  final stem = flavor == null ? 'app-$mode' : 'app-$flavor-$mode';
  return _firstExisting(apkDir, '$stem.apk', extension: '.apk');
}

/// Locates the AAB produced by `flutter build appbundle`.
///
/// Gradle puts bundles under `build/app/outputs/bundle/{folder}/` where
/// `folder` is `{mode}` (no flavor) or `{flavor}{Mode}` (with flavor,
/// camelCase). The file itself is `app-{flavor?}-{mode}.aab`.
File? findAabArtifact(
  String projectRoot, {
  required String mode,
  String? flavor,
}) {
  final folder = flavor == null ? mode : '$flavor${_capitalize(mode)}';
  final aabDir = p.join(
    projectRoot,
    'build',
    'app',
    'outputs',
    'bundle',
    folder,
  );
  final stem = flavor == null ? 'app-$mode' : 'app-$flavor-$mode';
  return _firstExisting(aabDir, '$stem.aab', extension: '.aab');
}

/// Returns the named file under [dir] if it exists, otherwise the only file
/// in [dir] matching [extension] if exactly one is present. `null` otherwise.
File? _firstExisting(String dir, String name, {required String extension}) {
  final canonical = File(p.join(dir, name));
  if (canonical.existsSync()) return canonical;

  final d = Directory(dir);
  if (!d.existsSync()) return null;
  final matches = d
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).toLowerCase().endsWith(extension))
      .toList();
  return matches.length == 1 ? matches.single : null;
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
