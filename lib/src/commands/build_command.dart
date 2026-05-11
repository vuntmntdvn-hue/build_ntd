import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/builder/output_template.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Build a Flutter APK and copy it to a name derived from a template.
class BuildCommand extends Command<int> {
  BuildCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'flavor',
        help: 'Flutter build flavor (e.g. dev, pro).',
      )
      ..addOption(
        'mode',
        allowed: ['release', 'debug', 'profile'],
        defaultsTo: 'release',
        help: 'Build mode passed to `flutter build apk`.',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'Entry-point Dart file forwarded to flutter build.',
      )
      ..addMultiOption(
        'dart-define',
        help: 'Forwarded to flutter build as --dart-define=key=value.',
      )
      ..addOption(
        'output-dir',
        help: 'Directory to copy the renamed APK into. '
            'Overrides `build_ntd.output_dir` in pubspec.yaml.',
      )
      ..addOption(
        'output-name',
        help: 'Template for the renamed APK. Overrides '
            '`build_ntd.output_name` in pubspec.yaml.',
      );
  }

  final Logger _logger;

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build an APK and copy it to a templated filename.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final projectRoot = Directory.current.path;

    final BuildConfig config;
    final GradleVersionInfo gradle;
    try {
      config = BuildConfig.load(projectRoot);
      gradle = GradleVersionInfo.load(projectRoot);
    } on BuildConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.config.code;
    }

    final flavor = args['flavor'] as String?;
    final mode = args['mode'] as String;
    final target = args['target'] as String?;
    final dartDefines = args['dart-define'] as List<String>;
    final overrideOutputDir = args['output-dir'] as String?;
    final overrideTemplate = args['output-name'] as String?;

    final now = DateTime.now();
    final variables = <String, String>{
      'appId': config.appId,
      'appname': config.appName,
      'versionName': gradle.versionName,
      'versionCode': gradle.versionCode,
      'buildDate': _formatDate(now),
      'buildTime': _formatTime(now),
      'flavor': flavor ?? '',
      'buildType': mode,
    };

    final template = overrideTemplate ?? config.outputNameTemplate;
    final String renamedFile;
    try {
      renamedFile = renderTemplate(template, variables);
    } on TemplateException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    final flutterArgs = <String>[
      'build',
      'apk',
      '--$mode',
      if (flavor != null) ...['--flavor', flavor],
      if (target != null) ...['--target', target],
      for (final d in dartDefines) '--dart-define=$d',
    ];

    _logger.info('Running: flutter ${flutterArgs.join(' ')}');
    final exitCode = await _runFlutter(flutterArgs);
    if (exitCode != 0) {
      _logger.err('flutter build apk failed with exit code $exitCode.');
      return ExitCode.software.code;
    }

    final sourceApk = _findBuiltApk(projectRoot, flavor: flavor, mode: mode);
    if (sourceApk == null) {
      _logger.err(
        'Build succeeded but the expected APK was not found under '
        'build/app/outputs/flutter-apk/.',
      );
      return ExitCode.software.code;
    }

    final destDir =
        overrideOutputDir ?? config.outputDir ?? sourceApk.parent.path;
    final destPath = p.join(destDir, renamedFile);
    try {
      Directory(destDir).createSync(recursive: true);
      sourceApk.copySync(destPath);
    } on FileSystemException catch (e) {
      _logger.err('Failed to copy APK: ${e.message}');
      return ExitCode.ioError.code;
    }

    _logger.info(lightGreen.wrap('APK copied to $destPath'));
    return ExitCode.success.code;
  }

  /// Streams flutter's stdout/stderr through the logger as it runs.
  Future<int> _runFlutter(List<String> args) async {
    final process = await Process.start(
      'flutter',
      args,
      runInShell: true,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  File? _findBuiltApk(
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
    final primary = File(p.join(apkDir, '$stem.apk'));
    if (primary.existsSync()) return primary;

    // Fallback: any file matching app*.apk (handles edge cases like custom
    // naming or split-per-abi single matches).
    final dir = Directory(apkDir);
    if (!dir.existsSync()) return null;
    final matches = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).endsWith('.apk'))
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  String _formatDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}.'
      '${t.month.toString().padLeft(2, '0')}.'
      '${t.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}.'
      '${t.minute.toString().padLeft(2, '0')}';
}
