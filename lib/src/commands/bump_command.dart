import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/version_code_writer.dart';
import 'package:mason_logger/mason_logger.dart';

/// Bump (or set) the Android `versionCode`.
class BumpCommand extends Command<int> {
  BumpCommand({required Logger logger}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'bump';

  @override
  String get description =>
      'Bump (or set) Android versionCode in build.gradle and pubspec.yaml.';

  @override
  String get invocation => '${runner!.executableName} $name [number]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    int? explicit;
    if (rest.length > 1) {
      _logger.err(
        'Expected at most one positional argument, got ${rest.length}: '
        '${rest.join(' ')}',
      );
      return ExitCode.usage.code;
    }
    if (rest.isNotEmpty) {
      explicit = int.tryParse(rest.single);
      if (explicit == null) {
        _logger.err(
          'Argument must be a positive integer (got "${rest.single}").',
        );
        return ExitCode.usage.code;
      }
    }

    final VersionCodeBump result;
    try {
      result = bumpVersionCode(Directory.current.path, explicit: explicit);
    } on VersionCodeException catch (e) {
      _logger.err(e.message);
      return ExitCode.config.code;
    }

    final from = result.oldValue?.toString() ?? '?';
    _logger.info(
      lightGreen.wrap('versionCode: $from → ${result.newValue}'),
    );
    for (final f in result.filesUpdated) {
      _logger.info('  updated $f');
    }
    return ExitCode.success.code;
  }
}
