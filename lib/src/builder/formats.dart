/// Formats a byte count for human display. Switches unit at the 1024
/// boundary and shows one decimal place once kilobytes or larger.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(1)} GB';
}

/// Formats a duration like a build log: `Xs` under a minute, `Xm Ys` under
/// an hour, `Xh Ym Ys` beyond.
String formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inHours}h '
      '${d.inMinutes.remainder(60)}m '
      '${d.inSeconds.remainder(60)}s';
}
