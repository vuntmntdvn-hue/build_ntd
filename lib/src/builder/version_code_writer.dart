import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Result of [bumpVersionCode].
class VersionCodeBump {
  VersionCodeBump({
    required this.oldValue,
    required this.newValue,
    required this.filesUpdated,
  });

  /// Previous version code if we could determine one. `null` means the caller
  /// supplied an explicit value and no readable source existed.
  final int? oldValue;
  final int newValue;

  /// Files that were rewritten, expressed as paths relative to the project
  /// root.
  final List<String> filesUpdated;
}

/// Bumps the Android `versionCode` for the Flutter project at [projectRoot].
///
/// - If [explicit] is supplied, sets the value to it. Must be `> 0`.
/// - Otherwise reads the current value (gradle literal first, then pubspec
///   `version: x.y.z+N`, matching how `apk` and `bundle` read it) and adds 1.
///
/// Writes to every file that holds a writable copy of the value, keeping them
/// in sync:
///
/// - If `android/app/build.gradle[.kts]` has a **literal** `versionCode N`,
///   it's updated. Dynamic references like `flutterVersionCode.toInteger()`
///   are left intact so the Flutter scaffolding still works.
/// - If `pubspec.yaml` has a `version:` field, its `+N` is updated (appended
///   if missing).
///
/// Errors if no file has a writable target.
VersionCodeBump bumpVersionCode(String projectRoot, {int? explicit}) {
  if (explicit != null && explicit <= 0) {
    throw VersionCodeException(
      'versionCode must be a positive integer (got $explicit).',
    );
  }

  final gradleFile = _findGradleFile(projectRoot);
  if (gradleFile == null) {
    throw VersionCodeException(
      'Could not find android/app/build.gradle[.kts]. '
      'Run this command from a Flutter project root.',
    );
  }

  final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
  final gradleSource = gradleFile.readAsStringSync();
  final pubspecSource =
      pubspecFile.existsSync() ? pubspecFile.readAsStringSync() : null;

  // Same priority `GradleVersionInfo` uses for reading.
  final fromGradle = _readGradleLiteral(gradleSource);
  final fromPubspec =
      pubspecSource != null ? _readPubspecVersionCode(pubspecSource) : null;
  final oldValue = fromGradle ?? fromPubspec;

  if (explicit == null && oldValue == null) {
    throw VersionCodeException(
      'Cannot determine current versionCode. Neither '
      'android/app/build.gradle[.kts] has a literal value nor '
      'pubspec.yaml has a `version:` line. '
      'Pass an explicit value, e.g. `build_ntd bump 1`.',
    );
  }

  final newValue = explicit ?? (oldValue! + 1);
  final updated = <String>[];

  // Update the gradle literal in place if there is one. Dynamic refs are
  // left alone — they'll pick up the new pubspec value at build time.
  final newGradle = _writeGradleLiteral(gradleSource, newValue);
  if (newGradle != null && newGradle != gradleSource) {
    gradleFile.writeAsStringSync(newGradle);
    updated.add(p.relative(gradleFile.path, from: projectRoot));
  }

  // Update pubspec `version:` if it has one — keeps both sources in sync.
  if (pubspecSource != null) {
    final newPubspec = _writePubspecVersionCode(pubspecSource, newValue);
    if (newPubspec != null && newPubspec != pubspecSource) {
      pubspecFile.writeAsStringSync(newPubspec);
      updated.add(p.relative(pubspecFile.path, from: projectRoot));
    }
  }

  if (updated.isEmpty) {
    throw VersionCodeException(
      'Nothing to update. android/app/build.gradle[.kts] uses a dynamic '
      'reference and pubspec.yaml has no `version:` field. Add a '
      '`version: 1.0.0+1` line to pubspec.yaml or replace the gradle '
      'dynamic ref with a literal.',
    );
  }

  return VersionCodeBump(
    oldValue: oldValue,
    newValue: newValue,
    filesUpdated: updated,
  );
}

File? _findGradleFile(String projectRoot) {
  for (final name in const ['build.gradle', 'build.gradle.kts']) {
    final f = File(p.join(projectRoot, 'android', 'app', name));
    if (f.existsSync()) return f;
  }
  return null;
}

/// Matches `versionCode 5` / `versionCode = 5` / `versionCode "5"`.
int? _readGradleLiteral(String source) {
  final re = RegExp(r'^\s*versionCode\s*=?\s*"?(\d+)"?', multiLine: true);
  final m = re.firstMatch(source);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Returns the build number from `version: x.y.z+N` in pubspec. If the
/// `version:` line is present but has no `+N`, returns `1` to mirror Flutter
/// (and `GradleVersionInfo`'s) default. Returns `null` when there is no
/// `version:` field at all.
int? _readPubspecVersionCode(String source) {
  final doc = loadYaml(source);
  if (doc is! YamlMap) return null;
  final version = doc['version']?.toString();
  if (version == null) return null;
  final plus = version.indexOf('+');
  if (plus == -1) return 1;
  return int.tryParse(version.substring(plus + 1));
}

/// Rewrites the first literal `versionCode <number>` line to
/// `versionCode $newValue`, preserving the assignment style (` ` vs ` = `).
///
/// Returns `null` if there is no literal versionCode line — dynamic
/// references like `versionCode flutterVersionCode.toInteger()` are left
/// untouched so they keep reading from pubspec.
String? _writeGradleLiteral(String source, int newValue) {
  // The trailing `"?\d+"?` is the literal value. Lines with a non-numeric
  // value (e.g. a dynamic reference) won't match.
  final re = RegExp(
    r'^(\s*)versionCode(\s*=?\s*)"?\d+"?',
    multiLine: true,
  );
  final m = re.firstMatch(source);
  if (m == null) return null;
  final indent = m.group(1) ?? '';
  final sep = _normalizeSeparator(m.group(2) ?? ' ');
  return source.replaceFirst(re, '${indent}versionCode$sep$newValue');
}

/// Ensures the separator between `versionCode` and the value is sane: either
/// a single space or ` = ` with surrounding spaces.
String _normalizeSeparator(String captured) {
  return captured.contains('=') ? ' = ' : ' ';
}

/// Rewrites `version: x.y.z+N` to use [newValue]. Appends `+<newValue>` if the
/// existing line has no `+N`. Returns `null` if there's no `version:` field.
String? _writePubspecVersionCode(String source, int newValue) {
  final re = RegExp(r'^(\s*version:\s*)(\S+)\s*$', multiLine: true);
  final m = re.firstMatch(source);
  if (m == null) return null;
  final prefix = m.group(1)!;
  final value = m.group(2)!;
  final plus = value.indexOf('+');
  final newVersion = plus == -1
      ? '$value+$newValue'
      : '${value.substring(0, plus)}+$newValue';
  return source.replaceFirst(re, '$prefix$newVersion');
}

class VersionCodeException implements Exception {
  VersionCodeException(this.message);
  final String message;
  @override
  String toString() => message;
}
