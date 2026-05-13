import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_ntd/src/builder/pubspec_sample.dart';
import 'package:mason_logger/mason_logger.dart';

/// Scaffolds a commented `build_ntd:` section into the current project's
/// pubspec.yaml and previews the filenames `apk` / `bundle` would produce.
class SampleCommand extends Command<int> {
  SampleCommand({required Logger logger}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'sample';

  @override
  String get description =>
      'Append a sample `build_ntd:` section to pubspec.yaml and show the '
      'output filenames it would produce.';

  @override
  Future<int> run() async {
    final projectRoot = Directory.current.path;

    final SampleResult result;
    try {
      result = writeBuildNtdSample(projectRoot);
    } on PubspecSampleException catch (e) {
      _logger.err(e.message);
      return ExitCode.config.code;
    }

    if (result.sectionAppended) {
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
    } else {
      _logger.info(
        '`build_ntd:` section already present in ${result.pubspecPath}.',
      );
    }

    final preview = previewOutputNames(projectRoot);
    if (preview != null) {
      _logger
        ..info('')
        ..info('Sample output names (no flavor, mode=release):')
        ..info('  apk:    ${preview.apk}')
        ..info('  bundle: ${preview.bundle}');
    }

    return ExitCode.success.code;
  }
}
