import 'dart:io';

import 'package:build_ntd/src/commands/apk_command.dart';
import 'package:mason_logger/mason_logger.dart';

/// Builds an APK (using [ApkCommand]'s pipeline) and then installs it on a
/// connected Android device via `adb install -r`.
class InstallCommand extends ApkCommand {
  InstallCommand({required super.logger});

  @override
  String get name => 'install';

  @override
  String get description =>
      'Build an APK, rename it, then install it on a connected Android '
      'device via adb.';

  @override
  Future<int> onBuildSuccess(File artifact) async {
    logger.info('Installing ${artifact.path} via adb...');
    final ProcessResult result;
    try {
      result = await Process.run(
        'adb',
        ['install', '-r', artifact.path],
        runInShell: true,
      );
    } on ProcessException {
      logger
        ..err('adb not found on PATH.')
        ..info(
          '  Install the Android SDK platform-tools and make sure `adb` '
          'is on your PATH.',
        );
      return ExitCode.unavailable.code;
    }

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();
    if (stdout.isNotEmpty) logger.info(stdout);
    if (stderr.isNotEmpty) logger.info(stderr);

    if (result.exitCode != 0) {
      logger.err('adb install failed with exit code ${result.exitCode}.');
      return ExitCode.software.code;
    }

    logger.info(lightGreen.wrap('Installed.'));
    return ExitCode.success.code;
  }
}
