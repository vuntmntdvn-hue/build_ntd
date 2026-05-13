## build_ntd

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A Dart CLI that wraps `flutter build apk` / `flutter build appbundle` and
copies the produced artifact to a filename derived from a template.

```text
App780_Muslim_v1.0.0(1)_2026.05.11_dev_release.apk
App780_Muslim_v1.0.0(1)_2026.05.11_dev_release.aab
```

---

## Install

From this repo:

```sh
dart pub global activate --source=path <path to this package>
```

Make sure pub's global bin directory is on your `PATH`
(`%LOCALAPPDATA%\Pub\Cache\bin` on Windows,
`~/.pub-cache/bin` on macOS/Linux).

## Configure

Inside the Flutter project you want to build, add a `build_ntd:` section to
`pubspec.yaml`:

```yaml
build_ntd:
  app_id: 780              # required
  app_name: Muslim         # required
  # output_name: "App${appId}_${appname}.apk"   # optional override
  # output_dir: ./dist                          # optional copy destination
```

`versionName` and `versionCode` are read from `android/app/build.gradle`
(or `build.gradle.kts`). When Gradle uses Flutter's dynamic references
(`flutterVersionName` / `flutterVersionCode`), the CLI falls back to the
`version:` field of `pubspec.yaml`.

## Usage

From the Flutter project root:

```sh
# APK
build_ntd apk    --flavor dev -t lib/main_dev.dart

# AAB
build_ntd bundle --flavor dev -t lib/main_dev.dart

# Bump versionCode by 1, or set it explicitly
build_ntd bump
build_ntd bump 12
```

Both commands accept the same options:

```text
--flavor       Flutter build flavor (e.g. dev, pro)
--mode         release (default), debug, profile
--target, -t   Entry-point Dart file
--dart-define  Forwarded as --dart-define=key=value (repeatable)
--output-dir   Override the destination directory
--output-name  Override the filename template
--no-copy      Skip copying the produced artifact to the clipboard
```

On success, the renamed artifact is also copied to the system clipboard
so you can paste it straight into a chat or upload dialog:

- **Windows**: pasted as the file itself in Explorer (Set-Clipboard).
- **macOS**: pasted as the file itself in Finder (osascript).
- **Linux**: pasted as the path text via `wl-copy` or `xclip` if either
  is installed; otherwise skipped with a note. True file-clipboard on
  Linux varies by desktop environment and isn't handled.

Pass `--no-copy` to disable on CI or scripts.

`output_name:` and `output_dir:` in `pubspec.yaml` are shared between the
two commands. The artifact extension (`.apk` / `.aab`) is appended — or
swapped in — automatically, so a template like `App${appname}.apk` works
for `bundle` too (it becomes `App${appname}.aab`).

### Template variables

The default templates are:

```text
App${appId}_${appname}_v${versionName}(${versionCode})_${buildDate}_${flavor}_${buildType}.apk
App${appId}_${appname}_v${versionName}(${versionCode})_${buildDate}_${flavor}_${buildType}.aab
```

| Variable        | Source                                                      |
|-----------------|-------------------------------------------------------------|
| `${appId}`      | `build_ntd.app_id` in `pubspec.yaml`                        |
| `${appname}`    | `build_ntd.app_name` in `pubspec.yaml`                      |
| `${versionName}`| `android/app/build.gradle[.kts]` (or pubspec `version:`)    |
| `${versionCode}`| `android/app/build.gradle[.kts]` (or pubspec `version:`)    |
| `${buildDate}`  | `DateTime.now()` as `YYYY.MM.DD`                            |
| `${buildTime}`  | `DateTime.now()` as `HH.mm` (opt-in; reference in template) |
| `${flavor}`     | `--flavor` CLI flag                                         |
| `${buildType}`  | `--mode` CLI flag                                           |

Unknown placeholders fail the build with a clear message — no silent
`Appnull_...apk` outputs.

## `bump` — Android versionCode

```sh
build_ntd bump        # current + 1
build_ntd bump 12     # set to exactly 12
```

`bump` reads the current value the same way `apk` and `bundle` do — gradle
literal first, then `pubspec.yaml` `version: x.y.z+N` — and writes back to
every file that has a writable copy of the value, keeping them in sync:

- If `android/app/build.gradle[.kts]` has a literal `versionCode N`, it's
  updated.
- A `flutterVersionCode.toInteger()` (or other dynamic) reference is
  **left alone** so the Flutter scaffolding keeps working — the new
  pubspec value flows through at build time.
- If `pubspec.yaml` has a `version:` field, its `+N` is updated (appended
  if missing).

The rest of each file is byte-identical, so comments and surrounding
lines are preserved.

If neither file has a readable value, pass an explicit value to seed the
first bump:

```sh
build_ntd bump 1
```

## Running Tests

```sh
dart test
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
