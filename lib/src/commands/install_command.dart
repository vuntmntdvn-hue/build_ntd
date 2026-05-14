import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/apk_locator.dart';
import 'package:mason_logger/mason_logger.dart';

/// Installs an existing APK on a connected Android device via `adb install`.
///
/// Does **not** build — see `apk` for that. Resolves the APK by:
/// - using the path verbatim when the argument contains a path separator;
/// - otherwise searching [apkSearchDirs] for a matching basename;
/// - or finding the most recently modified `.apk` across those dirs when no
///   argument (or `--latest`) is given.
class InstallCommand extends Command<int> {
  InstallCommand({required Logger logger}) : _logger = logger {
    argParser.addFlag(
      'latest',
      negatable: false,
      help: 'Install the most recently modified APK from the search '
          'locations. Implied when no filename argument is given.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Install an existing APK on a connected Android device via adb.';

  @override
  String get invocation =>
      '${runner!.executableName} $name [<apk-file>] [--latest]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final wantLatest = argResults!['latest'] as bool;

    if (rest.length > 1) {
      _logger.err(
        'Expected at most one positional argument, got ${rest.length}: '
        '${rest.join(' ')}',
      );
      return ExitCode.usage.code;
    }
    if (rest.isNotEmpty && wantLatest) {
      _logger.err(
        '--latest cannot be combined with a filename argument.',
      );
      return ExitCode.usage.code;
    }

    final projectRoot = Directory.current.path;
    final searchDirs = apkSearchDirs(projectRoot);

    final File? resolved;
    if (rest.isEmpty) {
      resolved = findLatestApk(searchDirs);
      if (resolved == null) {
        _logger.err(
          'No APK found in any of the search locations:\n'
          '${searchDirs.map((d) => '  $d').join('\n')}',
        );
        return ExitCode.noInput.code;
      }
      _logger.info(darkGray.wrap('Latest: ${resolved.path}'));
    } else {
      final arg = rest.single;
      resolved = findApkByName(arg, searchDirs);
      if (resolved == null) {
        final tried = apkCandidatePaths(arg, searchDirs);
        _logger.err(
          'APK not found: $arg\n'
          'Looked in:\n${tried.map((path) => '  $path').join('\n')}',
        );
        return ExitCode.noInput.code;
      }
    }

    return _runAdbInstall(resolved);
  }

  Future<int> _runAdbInstall(File apk) async {
    _logger.info('Installing ${apk.path} via adb...');
    final ProcessResult result;
    try {
      result = await Process.run(
        'adb',
        ['install', '-r', apk.path],
        runInShell: true,
      );
    } on ProcessException {
      _logger
        ..err('adb not found on PATH.')
        ..info(
          '  Install the Android SDK platform-tools and make sure `adb` '
          'is on your PATH.',
        );
      return ExitCode.unavailable.code;
    }

    final stdoutText = (result.stdout as String).trim();
    final stderrText = (result.stderr as String).trim();
    if (stdoutText.isNotEmpty) _logger.info(stdoutText);
    if (stderrText.isNotEmpty) _logger.info(stderrText);

    if (result.exitCode != 0) {
      _logger.err('adb install failed with exit code ${result.exitCode}.');
      return ExitCode.software.code;
    }
    _logger.info(lightGreen.wrap('Installed.'));
    return ExitCode.success.code;
  }
}
