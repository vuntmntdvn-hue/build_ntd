import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/builder/clipboard.dart';
import 'package:build_ntd/src/builder/formats.dart';
import 'package:build_ntd/src/builder/output_template.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Shared orchestration for `build_ntd apk` and `build_ntd bundle`.
///
/// Subclasses declare what's different — the Flutter subcommand to run, the
/// artifact extension, the default filename template, and how to locate the
/// produced file — and the base handles everything else: config loading,
/// template rendering, process invocation, and copying.
abstract class AndroidBuildCommand extends Command<int> {
  AndroidBuildCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'flavor',
        help: 'Flutter build flavor — whatever names your project '
            'declares (e.g. dev, production).',
      )
      ..addOption(
        'mode',
        allowed: ['release', 'debug', 'profile'],
        defaultsTo: 'release',
        help: 'Build mode passed to flutter build.',
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
        help: 'Directory to copy the renamed artifact into. '
            'Overrides `build_ntd.output_dir` in pubspec.yaml.',
      )
      ..addOption(
        'output-name',
        help: 'Template for the renamed artifact. Overrides '
            '`build_ntd.output_name` in pubspec.yaml. The correct extension '
            'is appended (or substituted) automatically.',
      )
      ..addFlag(
        'copy',
        defaultsTo: true,
        help: 'Copy the produced artifact to the system clipboard on '
            'success. Use --no-copy to disable.',
      );
  }

  final Logger _logger;

  // ---- Subclass hooks ----

  /// The flutter subcommand to invoke: `apk` or `appbundle`.
  String get flutterSubcommand;

  /// The artifact extension including the dot, e.g. `.apk` or `.aab`.
  String get artifactExtension;

  /// Template to use when neither `output_name:` in pubspec nor `--output-name`
  /// on the CLI is supplied.
  String get defaultOutputName;

  /// Returns the file that flutter produced for the given mode/flavor, or
  /// `null` if it can't be located.
  File? findArtifact(
    String projectRoot, {
    required String mode,
    String? flavor,
  });

  // ---- Shared run() ----

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

    final template =
        overrideTemplate ?? config.outputNameTemplate ?? defaultOutputName;
    final String renamedFile;
    try {
      final rendered = renderTemplate(template, variables);
      final tidied = tidyOutputName(rendered);
      renamedFile = enforceExtension(tidied, artifactExtension);
    } on TemplateException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    final flutterArgs = <String>[
      'build',
      flutterSubcommand,
      '--$mode',
      if (flavor != null) ...['--flavor', flavor],
      if (target != null) ...['--target', target],
      for (final d in dartDefines) '--dart-define=$d',
    ];

    _logger.info('Running: flutter ${flutterArgs.join(' ')}');
    final stopwatch = Stopwatch()..start();
    final exitCode = await _runFlutter(flutterArgs);
    stopwatch.stop();
    if (exitCode != 0) {
      _logger.err('flutter build $flutterSubcommand failed '
          'with exit code $exitCode.');
      return ExitCode.software.code;
    }

    final sourceFile = findArtifact(projectRoot, mode: mode, flavor: flavor);
    if (sourceFile == null) {
      _logger.err(
        'Build succeeded but the expected $artifactExtension was not found.',
      );
      return ExitCode.software.code;
    }

    final destDir =
        overrideOutputDir ?? config.outputDir ?? sourceFile.parent.path;
    final destPath = p.join(destDir, renamedFile);
    try {
      Directory(destDir).createSync(recursive: true);
      sourceFile.copySync(destPath);
    } on FileSystemException catch (e) {
      _logger.err('Failed to copy artifact: ${e.message}');
      return ExitCode.ioError.code;
    }

    final size = formatBytes(File(destPath).lengthSync());
    final duration = formatDuration(stopwatch.elapsed);
    _logger.info(
      lightGreen.wrap(
        'Artifact copied to $destPath ($size, built in $duration)',
      ),
    );

    if (args['copy'] as bool) {
      await _putOnClipboard(destPath);
    }

    return ExitCode.success.code;
  }

  Future<void> _putOnClipboard(String path) async {
    final result = await copyFileToClipboard(path);
    switch (result.outcome) {
      case ClipboardOutcome.copied:
        final detail = result.detail == null ? '' : ' (${result.detail})';
        _logger.info(darkGray.wrap('  copied to clipboard$detail'));
      case ClipboardOutcome.toolMissing:
        _logger.info(
          darkGray.wrap('  clipboard skipped: ${result.detail}'),
        );
      case ClipboardOutcome.failed:
        _logger.info(
          darkGray.wrap('  clipboard copy failed: ${result.detail}'),
        );
      case ClipboardOutcome.unsupportedPlatform:
        _logger.detail(
          'Skipped clipboard: unsupported platform ${result.detail}',
        );
    }
  }

  Future<int> _runFlutter(List<String> args) async {
    final process = await Process.start(
      'flutter',
      args,
      runInShell: true,
      mode: ProcessStartMode.inheritStdio,
    );
    return process.exitCode;
  }

  String _formatDate(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}.'
      '${t.month.toString().padLeft(2, '0')}.'
      '${t.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}.'
      '${t.minute.toString().padLeft(2, '0')}';
}
