## build_ntd

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

A Dart CLI that wraps `flutter build apk` / `flutter build appbundle` and
copies the produced artifact to a filename derived from a template.

```text
App780_Muslim_v1.0.0(1)_2026.05.13_14.30_dev_release.apk
App780_Muslim_v1.0.0(1)_2026.05.13_14.30_dev_release.aab
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

The fastest path: run

```sh
build_ntd sample
```

from your Flutter project root. It appends a fully-commented `build_ntd:`
section to `pubspec.yaml`, auto-filling `app_name` from your project's
`name:` and using a placeholder for `app_id`. Edit `app_id` and you're done.

Or write the section by hand:

```yaml
build_ntd:
  app_id: "780"            # required
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

# Install an existing APK on a connected Android device (via adb)
build_ntd install App780_Muslim_v1.0.0(5)_..._release.apk   # by name
build_ntd install --latest                                  # most recent .apk
build_ntd install                                           # implied --latest

# Bump versionCode by 1, or set it explicitly
build_ntd bump
build_ntd bump 12

# Print a diagnostic dump of how build_ntd reads this project
build_ntd doctor
```

Both commands accept the same options:

```text
--flavor       Flutter build flavor — whatever names your project declares
               (e.g. dev, production, etc.)
--mode         release (default), debug, profile
--target, -t   Entry-point Dart file
--dart-define  Forwarded as --dart-define=key=value (repeatable)
--output-dir   Override the destination directory
--output-name  Override the filename template
--no-copy      Skip copying the produced artifact to the clipboard
--no-record    Skip writing a row to build_ntd_records.md
```

On success, the renamed artifact is also copied to the system clipboard
so you can paste it straight into a chat or upload dialog:

- **Windows**: pasted as the file itself in Explorer (Set-Clipboard).
- **macOS**: pasted as the file itself in Finder (osascript).
- **Linux**: pasted as the path text via `wl-copy` or `xclip` if either
  is installed; otherwise skipped with a note. True file-clipboard on
  Linux varies by desktop environment and isn't handled.

Pass `--no-copy` to disable on CI or scripts.

## `install` — push an APK to a device

```sh
build_ntd install <apk-file>   # explicit, by basename or path
build_ntd install --latest     # most recently modified .apk
build_ntd install              # same as --latest
```

`install` does **not** build — pair it with a prior `build_ntd apk`.
The argument can be a basename (resolved in the search locations below)
or a path. Without an argument (or with `--latest`), the most recently
modified `.apk` across the search locations is installed.

Search order for basename / `--latest`:

1. Project root (current working directory)
2. `output_dir` from pubspec's `build_ntd:` section (if set)
3. `build/app/outputs/flutter-apk/` (Flutter's default APK landing zone)

Under the hood: `adb install -r <path>` — `adb` must be on PATH.

## Build records

Every successful `apk` / `bundle` / `install` appends a row to
`build_ntd_records.md` at the project root, so you can look up which
commit a given APK came from weeks later:

```markdown
# build_ntd build records

| When             | Artifact                                                 | Commit  | Branch | Status |
|------------------|----------------------------------------------------------|---------|--------|--------|
| 2026-05-13 14:30 | App780_Muslim_v1.0.0(5)_2026.05.13_14.30_dev_release.apk | a1b2c3d | main   | clean  |
| 2026-05-13 15:45 | App780_Muslim_v1.0.0(6)_2026.05.13_15.45_dev_release.aab | b2c3d4e | main   | dirty  |
```

Git info comes from the local `git` CLI. When the project isn't a git
repo (or `git` isn't installed) the commit/branch/status columns show
em-dashes; the artifact row still gets written.

Pass `--no-record` to suppress the append (CI, scripts, throwaway
builds). Whether to commit `build_ntd_records.md` to your repo is your
call — it's not added to `.gitignore` automatically.

`output_name:` and `output_dir:` in `pubspec.yaml` are shared between the
two commands. The artifact extension (`.apk` / `.aab`) is appended — or
swapped in — automatically, so a template like `App${appname}.apk` works
for `bundle` too (it becomes `App${appname}.aab`).

### Template variables

The default templates are:

```text
App${appId}_${appname}_v${versionName}(${versionCode})_${buildDate}_${buildTime}_${flavor}_${buildType}.apk
App${appId}_${appname}_v${versionName}(${versionCode})_${buildDate}_${buildTime}_${flavor}_${buildType}.aab
```

| Variable        | Source                                                   |
|-----------------|----------------------------------------------------------|
| `${appId}`      | `build_ntd.app_id` in `pubspec.yaml`                     |
| `${appname}`    | `build_ntd.app_name` in `pubspec.yaml`                   |
| `${versionName}`| `android/app/build.gradle[.kts]` (or pubspec `version:`) |
| `${versionCode}`| `android/app/build.gradle[.kts]` (or pubspec `version:`) |
| `${buildDate}`  | `DateTime.now()` as `YYYY.MM.DD`                         |
| `${buildTime}`  | `DateTime.now()` as `HH.mm`                              |
| `${flavor}`     | `--flavor` CLI flag (empty when not passed)              |
| `${buildType}`  | `--mode` CLI flag                                        |

Empty placeholders (e.g. `${flavor}` when `--flavor` isn't passed) don't
leave behind double underscores — runs of `_` in the basename are
collapsed automatically, so `App780_..._14.30__release.apk` becomes
`App780_..._14.30_release.apk`.

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
