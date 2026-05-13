import 'dart:io';

import 'package:build_ntd/src/builder/android_artifact_path.dart';
import 'package:build_ntd/src/builder/build_config.dart';
import 'package:build_ntd/src/commands/android_build_command.dart';

/// Builds a Flutter APK and copies it to a name derived from a template.
class BuildCommand extends AndroidBuildCommand {
  BuildCommand({required super.logger});

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build an APK and copy it to a templated filename.';

  @override
  String get flutterSubcommand => 'apk';

  @override
  String get artifactExtension => '.apk';

  @override
  String get defaultOutputName => defaultOutputNameTemplate;

  @override
  File? findArtifact(
    String projectRoot, {
    required String mode,
    String? flavor,
  }) =>
      findApkArtifact(projectRoot, mode: mode, flavor: flavor);
}
