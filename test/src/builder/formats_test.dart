import 'package:build_ntd/src/builder/formats.dart';
import 'package:test/test.dart';

void main() {
  group('formatBytes', () {
    test('shows raw bytes below 1 KB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('switches to KB at 1024 and uses one decimal', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1023), '1023.0 KB');
    });

    test('switches to MB at 1 MiB', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      // ~23.5 MB — a typical flutter APK
      expect(formatBytes(24641536), '23.5 MB');
    });

    test('switches to GB at 1 GiB', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(formatBytes(1024 * 1024 * 1024 * 2), '2.0 GB');
    });
  });

  group('formatDuration', () {
    test('uses seconds under a minute', () {
      expect(formatDuration(Duration.zero), '0s');
      expect(formatDuration(const Duration(seconds: 12)), '12s');
      expect(formatDuration(const Duration(seconds: 59)), '59s');
    });

    test('uses Xm Ys at one minute and above', () {
      expect(formatDuration(const Duration(minutes: 1)), '1m 0s');
      expect(
        formatDuration(const Duration(minutes: 1, seconds: 45)),
        '1m 45s',
      );
      expect(
        formatDuration(const Duration(minutes: 59, seconds: 59)),
        '59m 59s',
      );
    });

    test('uses Xh Ym Ys at an hour and above', () {
      expect(formatDuration(const Duration(hours: 1)), '1h 0m 0s');
      expect(
        formatDuration(const Duration(hours: 2, minutes: 5, seconds: 30)),
        '2h 5m 30s',
      );
    });
  });
}
