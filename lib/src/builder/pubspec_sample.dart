import 'dart:io';

import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/builder/output_template.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Result of [writeBuildNtdSample].
class SampleResult {
  SampleResult({
    required this.pubspecPath,
    required this.appNameUsed,
    required this.sectionAppended,
  });

  /// Relative path of the pubspec file.
  final String pubspecPath;

  /// The value living under `app_name:` — either freshly written or read from
  /// the existing section.
  final String appNameUsed;

  /// `true` if this call appended a new section, `false` if a `build_ntd:`
  /// section was already present and we left it alone.
  final bool sectionAppended;
}

/// Sample filename preview produced by [previewOutputNames].
class OutputPreview {
  OutputPreview({required this.apk, required this.bundle});
  final String apk;
  final String bundle;
}

/// Fallback `app_name` when the host pubspec has no `name:` field.
const _fallbackAppName = 'my_flutter_app';

/// Appends a fully-commented `build_ntd:` section to `pubspec.yaml` at
/// [projectRoot] if one isn't already present.
///
/// - Auto-fills `app_name` from the host pubspec's `name:` field when
///   available, otherwise uses [_fallbackAppName].
/// - If `build_ntd:` already exists, the file is left untouched and the
///   returned [SampleResult.sectionAppended] is `false`.
/// - Normalizes trailing whitespace so the file ends with a single newline.
///
/// Throws [PubspecSampleException] only for unrecoverable errors (missing
/// pubspec.yaml).
SampleResult writeBuildNtdSample(String projectRoot) {
  final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    throw PubspecSampleException('pubspec.yaml not found at $pubspecPath');
  }

  final source = file.readAsStringSync();
  final doc = source.trim().isEmpty ? null : loadYaml(source);
  final relativePath = p.relative(pubspecPath, from: projectRoot);

  // Section already present — leave the file alone, return existing app_name.
  if (doc is YamlMap && doc['build_ntd'] != null) {
    final section = doc['build_ntd'];
    final appName = section is YamlMap
        ? section['app_name']?.toString() ?? ''
        : '';
    return SampleResult(
      pubspecPath: relativePath,
      appNameUsed: appName,
      sectionAppended: false,
    );
  }

  final projectName =
      (doc is YamlMap ? doc['name']?.toString() : null) ?? _fallbackAppName;
  final trimmed = source.replaceAll(RegExp(r'\s+$'), '');
  final separator = trimmed.isEmpty ? '' : '\n\n';
  final newContent = '$trimmed$separator${_renderSection(projectName)}\n';
  file.writeAsStringSync(newContent);

  return SampleResult(
    pubspecPath: relativePath,
    appNameUsed: projectName,
    sectionAppended: true,
  );
}

/// Renders sample APK and AAB filenames using values from the project's
/// `build_ntd:` block, gradle (or pubspec) version info, and the current
/// date/time. The preview always uses an empty flavor (so the underscore
/// tidy collapses it) and `release` for `buildType`.
///
/// Returns `null` if the project doesn't have a usable `build_ntd:` block
/// (e.g. `app_id` or `app_name` missing). When version info can't be read,
/// uses `<x.y.z>` / `<N>` as placeholders so the preview still works.
OutputPreview? previewOutputNames(String projectRoot) {
  final BuildConfig config;
  try {
    config = BuildConfig.load(projectRoot);
  } on BuildConfigException {
    return null;
  }

  var versionName = '<x.y.z>';
  var versionCode = '<N>';
  try {
    final gradle = GradleVersionInfo.load(projectRoot);
    versionName = gradle.versionName;
    versionCode = gradle.versionCode;
  } on BuildConfigException {
    // No gradle file (typical fresh project before `flutter create`). Try
    // reading `version:` from pubspec directly — same semantics as gradle's
    // dynamic-ref fallback.
    final fromPubspec = _tryReadPubspecVersion(projectRoot);
    if (fromPubspec != null) {
      versionName = fromPubspec.$1;
      versionCode = fromPubspec.$2;
    }
  }

  final now = DateTime.now();
  final variables = <String, String>{
    'appId': config.appId,
    'appname': config.appName,
    'versionName': versionName,
    'versionCode': versionCode,
    'buildDate': _formatDate(now),
    'buildTime': _formatTime(now),
    'flavor': '',
    'buildType': 'release',
  };

  String render(String template, String extension) {
    final rendered = renderTemplate(template, variables);
    return enforceExtension(tidyOutputName(rendered), extension);
  }

  // Custom output_name applies to both apk and bundle; each command swaps
  // its own extension. If unset, fall back to the format-specific defaults.
  final apkTemplate =
      config.outputNameTemplate ?? defaultOutputNameTemplate;
  final bundleTemplate =
      config.outputNameTemplate ?? defaultBundleOutputNameTemplate;

  return OutputPreview(
    apk: render(apkTemplate, '.apk'),
    bundle: render(bundleTemplate, '.aab'),
  );
}

/// Parses `version: x.y.z+N` from pubspec.yaml. Returns `(name, code)` —
/// build number defaults to `'1'` when `+N` is missing, matching how
/// [GradleVersionInfo] handles the dynamic-ref fallback.
(String, String)? _tryReadPubspecVersion(String projectRoot) {
  final file = File(p.join(projectRoot, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final doc = loadYaml(file.readAsStringSync());
  if (doc is! YamlMap) return null;
  final version = doc['version']?.toString();
  if (version == null) return null;
  final parts = version.split('+');
  return (parts[0], parts.length > 1 ? parts[1] : '1');
}

String _formatDate(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}.'
    '${t.month.toString().padLeft(2, '0')}.'
    '${t.day.toString().padLeft(2, '0')}';

String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}.'
    '${t.minute.toString().padLeft(2, '0')}';

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
