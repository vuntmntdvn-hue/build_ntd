import 'dart:io';

import 'package:build_ntd/src/builder/android_artifact_path.dart';
import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/commands/android_build_command.dart';

/// Builds a Flutter app bundle (AAB) and copies it to a name derived from a
/// template.
class BundleCommand extends AndroidBuildCommand {
  BundleCommand({required super.logger});

  @override
  String get name => 'bundle';

  @override
  String get description =>
      'Build an AAB and copy it to a templated filename.';

  @override
  String get flutterSubcommand => 'appbundle';

  @override
  String get artifactExtension => '.aab';

  @override
  String get defaultOutputName => defaultBundleOutputNameTemplate;

  @override
  File? findArtifact(
    String projectRoot, {
    required String mode,
    String? flavor,
  }) =>
      findAabArtifact(projectRoot, mode: mode, flavor: flavor);
}
