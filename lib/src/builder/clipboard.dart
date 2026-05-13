import 'dart:io';

/// How a [copyFileToClipboard] call resolved.
enum ClipboardOutcome {
  /// File reference (or path text, on Linux) is now on the clipboard.
  copied,

  /// Running on something other than Windows / macOS / Linux.
  unsupportedPlatform,

  /// The platform tool we need (PowerShell, osascript, wl-copy/xclip)
  /// isn't installed or isn't on PATH.
  toolMissing,

  /// The tool ran but reported failure.
  failed,
}

class ClipboardResult {
  ClipboardResult({required this.outcome, this.detail});
  final ClipboardOutcome outcome;
  final String? detail;
}

/// Copies the file at [path] to the system clipboard.
///
/// - **Windows**: file reference via `Set-Clipboard -LiteralPath`. Pasting in
///   Explorer pastes the file itself.
/// - **macOS**: file reference via `osascript` + POSIX file. Pasting in
///   Finder pastes the file itself.
/// - **Linux**: copies the path as text via `wl-copy` (Wayland) or `xclip`
///   (X11). True file clipboard on Linux needs MIME-type negotiation that
///   varies across desktop environments — out of scope.
///
/// Never throws. Failure modes are returned via [ClipboardResult.outcome].
Future<ClipboardResult> copyFileToClipboard(String path) async {
  try {
    if (Platform.isWindows) return await _copyWindows(path);
    if (Platform.isMacOS) return await _copyMacOS(path);
    if (Platform.isLinux) return await _copyLinux(path);
    return ClipboardResult(
      outcome: ClipboardOutcome.unsupportedPlatform,
      detail: Platform.operatingSystem,
    );
  } on Object catch (e) {
    return ClipboardResult(
      outcome: ClipboardOutcome.failed,
      detail: e.toString(),
    );
  }
}

Future<ClipboardResult> _copyWindows(String path) async {
  // PowerShell single-quoted strings are literal; escape `'` by doubling.
  final escaped = path.replaceAll("'", "''");
  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Set-Clipboard -LiteralPath '$escaped'",
    ]);
    if (result.exitCode == 0) {
      return ClipboardResult(outcome: ClipboardOutcome.copied);
    }
    return ClipboardResult(
      outcome: ClipboardOutcome.failed,
      detail: (result.stderr as String).trim(),
    );
  } on ProcessException {
    return ClipboardResult(
      outcome: ClipboardOutcome.toolMissing,
      detail: 'powershell.exe not found on PATH',
    );
  }
}

Future<ClipboardResult> _copyMacOS(String path) async {
  // AppleScript double-quoted strings need `\` and `"` escaped.
  final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  try {
    final result = await Process.run('osascript', [
      '-e',
      'set the clipboard to (POSIX file "$escaped")',
    ]);
    if (result.exitCode == 0) {
      return ClipboardResult(outcome: ClipboardOutcome.copied);
    }
    return ClipboardResult(
      outcome: ClipboardOutcome.failed,
      detail: (result.stderr as String).trim(),
    );
  } on ProcessException {
    return ClipboardResult(
      outcome: ClipboardOutcome.toolMissing,
      detail: 'osascript not found on PATH',
    );
  }
}

Future<ClipboardResult> _copyLinux(String path) async {
  // Try Wayland first, then X11. Either copies the path as text — it can
  // be pasted in a terminal but won't paste as a file in a file manager.
  for (final cmd in const ['wl-copy', 'xclip']) {
    try {
      final args = cmd == 'xclip' ? ['-selection', 'clipboard'] : <String>[];
      final process = await Process.start(cmd, args);
      process.stdin.write(path);
      await process.stdin.close();
      final code = await process.exitCode;
      if (code == 0) {
        return ClipboardResult(
          outcome: ClipboardOutcome.copied,
          detail: '$cmd (path as text)',
        );
      }
    } on ProcessException {
      // Not installed — try the next.
      continue;
    }
  }
  return ClipboardResult(
    outcome: ClipboardOutcome.toolMissing,
    detail: 'install wl-copy or xclip to enable',
  );
}
