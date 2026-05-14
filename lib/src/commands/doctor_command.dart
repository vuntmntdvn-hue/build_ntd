import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/builder/pubspec_sample.dart';
import 'package:build_ntd/src/version.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Prints a diagnostic dump of what `build_ntd` sees in the current project,
/// without running flutter. Useful when something behaves unexpectedly.
class DoctorCommand extends Command<int> {
  DoctorCommand({required Logger logger}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Print a diagnostic of how build_ntd reads the current project.';

  @override
  Future<int> run() async {
    final root = Directory.current.path;
    _logger.info(
      'build_ntd $packageVersion — diagnostic for $root',
    );

    _projectFiles(root);
    _configuration(root);
    _versionInfo(root);
    _templatesAndPreview(root);
    await _tools();

    return ExitCode.success.code;
  }

  // ----- Sections -----

  void _projectFiles(String root) {
    _section('Project files');
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    _row('pubspec.yaml', pubspec.existsSync() ? 'found' : 'NOT FOUND');

    final groovy = File(p.join(root, 'android', 'app', 'build.gradle'));
    final kts = File(p.join(root, 'android', 'app', 'build.gradle.kts'));
    final String gradleStatus;
    if (groovy.existsSync()) {
      gradleStatus = 'build.gradle (Groovy)';
    } else if (kts.existsSync()) {
      gradleStatus = 'build.gradle.kts (Kotlin DSL)';
    } else {
      gradleStatus = 'NOT FOUND';
    }
    _row('android gradle', gradleStatus);
  }

  void _configuration(String root) {
    _section('Configuration (build_ntd: in pubspec.yaml)');
    final BuildConfig config;
    try {
      config = BuildConfig.load(root);
    } on BuildConfigException catch (e) {
      _logger.info(
        lightYellow.wrap(
          '  ${e.message} '
          '— run `build_ntd sample` to scaffold it',
        ),
      );
      return;
    }

    _row('app_id', '"${config.appId}"');
    _row('app_name', config.appName);
    _row(
      'output_name',
      config.outputNameTemplate ?? darkGray.wrap('(default)') ?? '(default)',
    );
    _row(
      'output_dir',
      config.outputDir ??
          darkGray.wrap('(alongside artifact)') ??
          '(alongside artifact)',
    );

    if (config.appId == '001') {
      _warn('app_id is still the placeholder "001" — set a real value');
    }
  }

  void _versionInfo(String root) {
    _section('Version info');

    final groovy = File(p.join(root, 'android', 'app', 'build.gradle'));
    final kts = File(p.join(root, 'android', 'app', 'build.gradle.kts'));
    final gradleFile = groovy.existsSync()
        ? groovy
        : (kts.existsSync() ? kts : null);
    final gradleSrc = gradleFile?.readAsStringSync() ?? '';

    final codeLiteral =
        RegExp(r'versionCode\s*=?\s*"?(\d+)"?').firstMatch(gradleSrc);
    final nameLiteral =
        RegExp(r'versionName\s*=?\s*"([^"]+)"').firstMatch(gradleSrc);
    final hasDynamicCode = gradleSrc.contains('flutterVersionCode');
    final hasDynamicName = gradleSrc.contains('flutterVersionName');

    try {
      final info = GradleVersionInfo.load(root);
      _row('versionName', '${info.versionName}  '
          '${_sourceLabel(nameLiteral != null, hasDynamicName)}');
      _row('versionCode', '${info.versionCode}  '
          '${_sourceLabel(codeLiteral != null, hasDynamicCode)}');
    } on BuildConfigException catch (e) {
      _logger.info(lightYellow.wrap('  ${e.message}'));
    }

    // Tweak 2: warn when both gradle and pubspec carry literal values and
    // they disagree. Gradle wins for reading; without a warning here the
    // discrepancy would be silent until someone wonders why their pubspec
    // build number doesn't match.
    final pubspec = _readPubspecVersion(root);
    if (pubspec != null) {
      if (codeLiteral != null && pubspec.code != null) {
        final gradleCode = codeLiteral.group(1);
        if (gradleCode != pubspec.code) {
          _warn(
            'versionCode mismatch: gradle says $gradleCode, '
            'pubspec says ${pubspec.code} (using gradle). '
            'Run `build_ntd bump $gradleCode` to sync.',
          );
        }
      }
      if (nameLiteral != null) {
        final gradleName = nameLiteral.group(1);
        if (gradleName != pubspec.name) {
          _warn(
            'versionName mismatch: gradle says "$gradleName", '
            'pubspec says "${pubspec.name}".',
          );
        }
      }
    }
  }

  /// Human-readable suffix describing where the resolved value came from.
  String _sourceLabel(bool hasLiteral, bool gradleHasDynamicRef) {
    if (hasLiteral) return '(gradle literal)';
    if (gradleHasDynamicRef) return '(pubspec, via gradle dynamic ref)';
    return '(pubspec)';
  }

  /// Parses pubspec.yaml's `version: x.y.z+N` field. Returns null when
  /// pubspec.yaml is missing or has no `version:` field.
  ({String name, String? code})? _readPubspecVersion(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final doc = loadYaml(pubspec.readAsStringSync());
    if (doc is! YamlMap) return null;
    final raw = doc['version']?.toString();
    if (raw == null) return null;
    final plus = raw.indexOf('+');
    if (plus == -1) return (name: raw, code: null);
    return (name: raw.substring(0, plus), code: raw.substring(plus + 1));
  }

  void _templatesAndPreview(String root) {
    _section('Templates in use');
    BuildConfig? config;
    try {
      config = BuildConfig.load(root);
    } on BuildConfigException {
      // Section already warned in _configuration.
    }
    _row('apk', config?.outputNameTemplate ?? defaultOutputNameTemplate);
    _row(
      'aab',
      config?.outputNameTemplate ?? defaultBundleOutputNameTemplate,
    );

    _section('Sample output names (no flavor, mode=release)');
    final preview = previewOutputNames(root);
    if (preview == null) {
      _logger.info(
        darkGray.wrap(
          '  (skipped — configuration is incomplete)',
        ),
      );
    } else {
      _row('apk', preview.apk);
      _row('bundle', preview.bundle);
    }
  }

  Future<void> _tools() async {
    _section('Tools');

    final flutter = await _runFor('flutter', const ['--version']);
    _toolRow('flutter', flutter);

    final adb = await _runFor('adb', const ['version']);
    _toolRow('adb', adb);

    final clipboardTool = _clipboardTool();
    _check('clipboard', true, detail: clipboardTool);
  }

  // ----- Helpers -----

  Future<_ToolResult> _runFor(String exe, List<String> args) async {
    try {
      // Decode as UTF-8 — many tools print Unicode bullets/arrows that
      // would otherwise garble under Windows' default systemEncoding.
      final result = await Process.run(
        exe,
        args,
        runInShell: true,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        return _ToolResult.error('exit code ${result.exitCode}');
      }
      final firstLine =
          (result.stdout as String).split('\n').first.trim();
      return _ToolResult.found(firstLine.isEmpty ? 'available' : firstLine);
    } on ProcessException {
      return _ToolResult.notFound();
    } on TimeoutException {
      return _ToolResult.error('timed out after 10s');
    }
  }

  String _clipboardTool() {
    if (Platform.isWindows) return 'powershell.exe (Windows native)';
    if (Platform.isMacOS) return 'osascript (macOS native)';
    if (Platform.isLinux) return 'wl-copy / xclip if installed';
    return Platform.operatingSystem;
  }

  void _section(String title) {
    _logger
      ..info('')
      ..info(lightCyan.wrap(title));
  }

  void _row(String key, String value) {
    _logger.info('  ${key.padRight(15)}$value');
  }

  void _warn(String message) {
    _logger.info(lightYellow.wrap('  [!] $message'));
  }

  void _check(String label, bool ok, {String detail = ''}) {
    final mark = ok ? lightGreen.wrap('[✓]') : lightRed.wrap('[✗]');
    _logger.info('  $mark ${label.padRight(10)}$detail');
  }

  void _toolRow(String name, _ToolResult result) {
    switch (result.status) {
      case _ToolStatus.found:
        _check(name, true, detail: result.detail);
      case _ToolStatus.notFound:
        _check(name, false, detail: 'not on PATH');
      case _ToolStatus.error:
        _logger.info(
          '  ${lightYellow.wrap('[!]')} ${name.padRight(10)}${result.detail}',
        );
    }
  }
}

enum _ToolStatus { found, notFound, error }

class _ToolResult {
  _ToolResult._(this.status, this.detail);
  factory _ToolResult.found(String detail) =>
      _ToolResult._(_ToolStatus.found, detail);
  factory _ToolResult.notFound() => _ToolResult._(_ToolStatus.notFound, '');
  factory _ToolResult.error(String detail) =>
      _ToolResult._(_ToolStatus.error, detail);

  final _ToolStatus status;
  final String detail;
}
