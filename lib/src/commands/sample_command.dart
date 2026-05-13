import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/pubspec_sample.dart';
import 'package:mason_logger/mason_logger.dart';

/// Scaffolds a commented `build_ntd:` section into the current project's
/// pubspec.yaml.
class SampleCommand extends Command<int> {
  SampleCommand({required Logger logger}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'sample';

  @override
  String get description =>
      'Append a sample `build_ntd:` section to pubspec.yaml.';

  @override
  Future<int> run() async {
    final SampleResult result;
    try {
      result = writeBuildNtdSample(Directory.current.path);
    } on PubspecSampleException catch (e) {
      _logger.err(e.message);
      return ExitCode.config.code;
    }

    _logger
      ..info(
        lightGreen.wrap(
          'Appended `build_ntd:` section to ${result.pubspecPath}',
        ),
      )
      ..info(
        '  app_name was set to "${result.appNameUsed}". '
        'Update `app_id` before your next build.',
      );
    return ExitCode.success.code;
  }
}
