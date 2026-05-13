import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:build_ntd/src/commands/commands.dart';
import 'package:build_ntd/src/version.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';

const executableName = 'build_ntd';
const packageName = 'build_ntd';
const description =
    'Build a Flutter APK or AAB and rename it from a template.';

/// {@template build_ntd_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```bash
/// $ build_ntd --version
/// ```
/// {@endtemplate}
class BuildNtdCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro build_ntd_command_runner}
  BuildNtdCommandRunner({Logger? logger})
    : _logger = logger ?? Logger(),
      super(executableName, description) {
    // Add root options and flags
    argParser
      ..addFlag(
        'version',
        abbr: 'v',
        negatable: false,
        help: 'Print the current version.',
      )
      ..addFlag(
        'verbose',
        help: 'Noisy logging, including all shell commands executed.',
      );

    // Add sub commands
    addCommand(BuildCommand(logger: _logger));
    addCommand(BundleCommand(logger: _logger));
  }

  @override
  void printUsage() => _logger.info(usage);

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['verbose'] == true) {
        _logger.level = Level.verbose;
      }
      return await runCommand(topLevelResults) ?? ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      _logger
        ..err(e.message)
        ..err('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Fast track completion command
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    // Verbose logs
    _logger
      ..detail('Argument information:')
      ..detail('  Top level options:');
    for (final option in topLevelResults.options) {
      if (topLevelResults.wasParsed(option)) {
        _logger.detail('  - $option: ${topLevelResults[option]}');
      }
    }
    if (topLevelResults.command != null) {
      final commandResult = topLevelResults.command!;
      _logger
        ..detail('  Command: ${commandResult.name}')
        ..detail('    Command options:');
      for (final option in commandResult.options) {
        if (commandResult.wasParsed(option)) {
          _logger.detail('    - $option: ${commandResult[option]}');
        }
      }
    }

    // Run the command or show version
    if (topLevelResults['version'] == true) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }
    return super.runCommand(topLevelResults);
  }
}
