import 'dart:convert';
import 'dart:io';

/// Git context for a project, gathered via the `git` CLI.
class GitInfo {
  GitInfo({
    required this.shortSha,
    required this.fullSha,
    required this.branch,
    required this.isDirty,
  });

  /// 7-character short SHA.
  final String shortSha;

  /// Full 40-character SHA.
  final String fullSha;

  /// Current branch name, or `null` when HEAD is detached.
  final String? branch;

  /// True when `git status --porcelain` reports any uncommitted changes.
  final bool isDirty;

  /// A single label suitable for log/table output:
  /// `clean`, `dirty`, or `detached` when there's no branch.
  String get statusLabel {
    if (branch == null) return 'detached';
    return isDirty ? 'dirty' : 'clean';
  }
}

/// Reads git context for the project at [projectRoot]. Returns `null` when
/// not in a git working tree, or when the `git` CLI is missing entirely.
/// Never throws.
Future<GitInfo?> readGitInfo(String projectRoot) async {
  try {
    final inRepo = await _git(projectRoot, const [
      'rev-parse',
      '--is-inside-work-tree',
    ]);
    if (inRepo.exitCode != 0) return null;

    final shaResult = await _git(projectRoot, const ['rev-parse', 'HEAD']);
    if (shaResult.exitCode != 0) return null;
    final fullSha = (shaResult.stdout as String).trim();
    if (fullSha.isEmpty) return null;
    final shortSha =
        fullSha.length >= 7 ? fullSha.substring(0, 7) : fullSha;

    // Detached HEAD → symbolic-ref exits non-zero; that's not an error here.
    String? branch;
    final branchResult = await _git(projectRoot, const [
      'symbolic-ref',
      '--short',
      'HEAD',
    ]);
    if (branchResult.exitCode == 0) {
      final value = (branchResult.stdout as String).trim();
      if (value.isNotEmpty) branch = value;
    }

    final statusResult =
        await _git(projectRoot, const ['status', '--porcelain']);
    final isDirty =
        (statusResult.stdout as String).trim().isNotEmpty;

    return GitInfo(
      shortSha: shortSha,
      fullSha: fullSha,
      branch: branch,
      isDirty: isDirty,
    );
  } on ProcessException {
    return null;
  }
}

Future<ProcessResult> _git(String workingDir, List<String> args) {
  return Process.run(
    'git',
    args,
    workingDirectory: workingDir,
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}
