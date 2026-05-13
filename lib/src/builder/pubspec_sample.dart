import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Result of [writeBuildNtdSample].
class SampleResult {
  SampleResult({required this.pubspecPath, required this.appNameUsed});

  /// Relative path of the file that was modified.
  final String pubspecPath;

  /// The value written into `app_name:` — either the project's `name:` from
  /// pubspec, or the fallback placeholder.
  final String appNameUsed;
}

/// Fallback `app_name` when the host pubspec has no `name:` field.
const _fallbackAppName = 'my_flutter_app';

/// Appends a fully-commented `build_ntd:` section to `pubspec.yaml` at
/// [projectRoot].
///
/// - Auto-fills `app_name` from the host pubspec's `name:` field when
///   available, otherwise uses [_fallbackAppName].
/// - Refuses if a `build_ntd:` section already exists.
/// - Normalizes trailing whitespace so the file ends with a single newline.
///
/// Throws [PubspecSampleException] for unrecoverable errors.
SampleResult writeBuildNtdSample(String projectRoot) {
  final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    throw PubspecSampleException('pubspec.yaml not found at $pubspecPath');
  }

  final source = file.readAsStringSync();
  final doc = source.trim().isEmpty ? null : loadYaml(source);

  if (doc is YamlMap && doc['build_ntd'] != null) {
    throw PubspecSampleException(
      'build_ntd: section already exists in pubspec.yaml. '
      'Remove it first or edit it manually.',
    );
  }

  final projectName =
      (doc is YamlMap ? doc['name']?.toString() : null) ?? _fallbackAppName;

  // Strip trailing whitespace then re-attach a single trailing newline.
  // Result: input pubspec  →  trimmed + "\n\n<section>\n"
  final trimmed = source.replaceAll(RegExp(r'\s+$'), '');
  final separator = trimmed.isEmpty ? '' : '\n\n';
  final newContent = '$trimmed$separator${_renderSection(projectName)}\n';
  file.writeAsStringSync(newContent);

  return SampleResult(
    pubspecPath: p.relative(pubspecPath, from: projectRoot),
    appNameUsed: projectName,
  );
}

String _renderSection(String projectName) =>
    '''
# Settings for the build_ntd CLI.
# Used by `build_ntd apk` and `build_ntd bundle` to derive the output
# filename of the produced artifact, and by `build_ntd bump` for
# versionCode management.
build_ntd:
  # Short identifier baked into the output filename (e.g. App780_...).
  app_id: "001"

  # Human-friendly name baked into the output filename
  # (e.g. App001_Muslim_...).
  app_name: $projectName

  # (Optional) Override the output filename template. \${var} placeholders
  # are substituted from pubspec, gradle, CLI flags, and build time.
  # See README for the full variable list. Default:
  #   App\${appId}_\${appname}_v\${versionName}(\${versionCode})_\${buildDate}_\${buildTime}_\${flavor}_\${buildType}.apk
  # output_name: "App\${appId}_\${appname}_\${flavor}_\${buildType}.apk"

  # (Optional) Directory to copy the renamed artifact into. Defaults to
  # the same directory Flutter wrote the original to.
  # output_dir: ./dist''';

class PubspecSampleException implements Exception {
  PubspecSampleException(this.message);
  final String message;
  @override
  String toString() => message;
}
