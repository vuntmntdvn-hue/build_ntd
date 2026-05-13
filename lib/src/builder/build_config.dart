import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _defaultOutputStem =
    r'App${appId}_${appname}_v${versionName}'
    r'(${versionCode})_${buildDate}_${buildTime}_${flavor}_${buildType}';

/// Default APK filename template when none is configured in `pubspec.yaml`.
const defaultOutputNameTemplate = '$_defaultOutputStem.apk';

/// Default AAB filename template when none is configured in `pubspec.yaml`.
const defaultBundleOutputNameTemplate = '$_defaultOutputStem.aab';

/// Settings read from the `build_ntd:` section of `pubspec.yaml`.
class BuildConfig {
  BuildConfig({
    required this.appId,
    required this.appName,
    required this.outputNameTemplate,
    required this.outputDir,
  });

  /// Loads config from `<projectRoot>/pubspec.yaml`.
  ///
  /// Throws [BuildConfigException] if the file is missing or the
  /// `build_ntd:` section is incomplete.
  factory BuildConfig.load(String projectRoot) {
    final pubspecPath = p.join(projectRoot, 'pubspec.yaml');
    final pubspecFile = File(pubspecPath);
    if (!pubspecFile.existsSync()) {
      throw BuildConfigException('pubspec.yaml not found at $pubspecPath');
    }

    final doc = loadYaml(pubspecFile.readAsStringSync());
    if (doc is! YamlMap) {
      throw BuildConfigException('pubspec.yaml is not a YAML map.');
    }

    final section = doc['build_ntd'];
    if (section is! YamlMap) {
      throw BuildConfigException(
        'Missing `build_ntd:` section in pubspec.yaml. '
        'Add it with at least `app_id` and `app_name`.',
      );
    }

    final appId = section['app_id'];
    if (appId == null) {
      throw BuildConfigException(
        'Missing `app_id` under `build_ntd:` in pubspec.yaml.',
      );
    }
    final appName = section['app_name'];
    if (appName == null) {
      throw BuildConfigException(
        'Missing `app_name` under `build_ntd:` in pubspec.yaml.',
      );
    }

    return BuildConfig(
      appId: appId.toString(),
      appName: appName.toString(),
      outputNameTemplate: section['output_name'] as String?,
      outputDir: section['output_dir'] as String?,
    );
  }

  final String appId;
  final String appName;

  /// User-supplied template. `null` means "use the command's default".
  /// Shared between APK and AAB commands; each command coerces the file
  /// extension via `enforceExtension` at the call site.
  final String? outputNameTemplate;

  /// Destination directory for the renamed artifact. `null` means "next to
  /// the original under `build/app/outputs/...`".
  final String? outputDir;
}

/// Version information extracted from the Android Gradle build script.
class GradleVersionInfo {
  GradleVersionInfo({required this.versionName, required this.versionCode});

  /// Reads `versionName` / `versionCode` from `android/app/build.gradle`
  /// (Groovy) or `android/app/build.gradle.kts` (Kotlin DSL). Falls back to
  /// the `version:` field of `pubspec.yaml` when Gradle uses Flutter's
  /// dynamic references (`flutter.versionName` / `flutterVersionName`).
  factory GradleVersionInfo.load(String projectRoot) {
    final candidates = [
      p.join(projectRoot, 'android', 'app', 'build.gradle'),
      p.join(projectRoot, 'android', 'app', 'build.gradle.kts'),
    ];
    final gradleFile = candidates.map(File.new).firstWhere(
      (f) => f.existsSync(),
      orElse: () => throw BuildConfigException(
        'Could not find android/app/build.gradle[.kts]. '
        'Run this command from a Flutter project root.',
      ),
    );

    final source = gradleFile.readAsStringSync();
    final name = _extractLiteralString(source, 'versionName');
    final code = _extractLiteralOrInt(source, 'versionCode');

    if (name != null && code != null) {
      return GradleVersionInfo(versionName: name, versionCode: code);
    }

    // Fall back to pubspec `version: x.y.z+n` for any value Gradle didn't
    // hard-code (the common Flutter template case).
    final fallback = _versionFromPubspec(projectRoot);
    return GradleVersionInfo(
      versionName: name ?? fallback.$1,
      versionCode: code ?? fallback.$2,
    );
  }

  final String versionName;
  final String versionCode;

  /// Matches `versionName "1.0.0"` or `versionName = "1.0.0"`.
  static String? _extractLiteralString(String source, String key) {
    final re = RegExp('$key\\s*=?\\s*"([^"\\\$]+)"');
    return re.firstMatch(source)?.group(1);
  }

  /// Matches `versionCode 1` / `versionCode = 1` / `versionCode "1"`.
  static String? _extractLiteralOrInt(String source, String key) {
    final str = _extractLiteralString(source, key);
    if (str != null) return str;
    final re = RegExp('$key\\s*=?\\s*(\\d+)');
    return re.firstMatch(source)?.group(1);
  }

  static (String, String) _versionFromPubspec(String projectRoot) {
    final doc = loadYaml(
      File(p.join(projectRoot, 'pubspec.yaml')).readAsStringSync(),
    );
    final version = (doc is YamlMap ? doc['version'] : null)?.toString();
    if (version == null) {
      throw BuildConfigException(
        'Gradle uses dynamic version references and no `version:` is set '
        'in pubspec.yaml.',
      );
    }
    final parts = version.split('+');
    final name = parts[0];
    final code = parts.length > 1 ? parts[1] : '1';
    return (name, code);
  }
}

class BuildConfigException implements Exception {
  BuildConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}
