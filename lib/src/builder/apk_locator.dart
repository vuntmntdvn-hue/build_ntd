import 'dart:io';

import 'package:build_ntd/src/builder/build_config.dart';
import 'package:path/path.dart' as p;

/// Ordered search dirs for resolving APK files when only a basename is given,
/// and for finding the most recent build with no argument.
///
/// Order: project root → pubspec `output_dir` (when set) → flutter's default
/// APK output (`build/app/outputs/flutter-apk`).
List<String> apkSearchDirs(String projectRoot) {
  final dirs = <String>[projectRoot];
  try {
    final config = BuildConfig.load(projectRoot);
    final outputDir = config.outputDir;
    if (outputDir != null) {
      dirs.add(
        p.isAbsolute(outputDir)
            ? outputDir
            : p.normalize(p.join(projectRoot, outputDir)),
      );
    }
  } on BuildConfigException {
    // No pubspec config — that's fine, the other locations still apply.
  }
  dirs.add(p.join(projectRoot, 'build', 'app', 'outputs', 'flutter-apk'));
  return dirs;
}

/// Resolves [basenameOrPath] to an existing file.
///
/// - Paths containing a separator (or absolute paths) are used verbatim —
///   the caller wrote out a specific location, honor it.
/// - Bare basenames are searched across [searchDirs] in order; the first
///   match wins.
File? findApkByName(String basenameOrPath, List<String> searchDirs) {
  if (_looksLikePath(basenameOrPath)) {
    final file = File(basenameOrPath);
    return file.existsSync() ? file : null;
  }
  for (final dir in searchDirs) {
    final candidate = File(p.join(dir, basenameOrPath));
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

/// Returns the most recently modified `*.apk` across [searchDirs] (top-level
/// only, no recursion). Returns null when no `.apk` files exist in any dir.
File? findLatestApk(List<String> searchDirs) {
  File? latest;
  DateTime? latestMtime;
  for (final dir in searchDirs) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final entity in d.listSync()) {
      if (entity is! File) continue;
      if (!p.basename(entity.path).toLowerCase().endsWith('.apk')) continue;
      final mtime = entity.statSync().modified;
      if (latestMtime == null || mtime.isAfter(latestMtime)) {
        latest = entity;
        latestMtime = mtime;
      }
    }
  }
  return latest;
}

/// The full list of candidate paths that [findApkByName] would try for
/// [basenameOrPath] — handy for "not found" error messages.
List<String> apkCandidatePaths(
  String basenameOrPath,
  List<String> searchDirs,
) {
  if (_looksLikePath(basenameOrPath)) return [basenameOrPath];
  return [for (final d in searchDirs) p.join(d, basenameOrPath)];
}

bool _looksLikePath(String s) =>
    s.contains('/') || s.contains(r'\') || p.isAbsolute(s);
