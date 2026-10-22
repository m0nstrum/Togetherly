import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/video_ux.dart';
import 'package:love_app/services/watch_videos_service.dart';

void main() {
  final created = DateTime(2026, 10, 1);
  test('срок хранения считается от даты заливки', () {
    expect(ForkVideoExpiry.expiresAt(created), DateTime(2026, 10, 31));
    expect(ForkVideoExpiry.daysLeft(created, DateTime(2026, 10, 29)), 2);
    expect(ForkVideoExpiry.daysLeft(created, DateTime(2026, 11, 5)), 0);
    expect(ForkVideoExpiry.daysLeft(null, DateTime(2026, 10, 1)), -1);
  });

  test('подпись плитки', () {
    expect(ForkVideoExpiry.tileLabel(null, created), '');
    expect(
      ForkVideoExpiry.tileLabel(created, DateTime(2026, 10, 30, 12)),
      contains(RegExp('завтра|tomorrow')),
    );
    expect(
      ForkVideoExpiry.tileLabel(created, DateTime(2026, 11, 2)),
      contains(RegExp('сегодня|today')),
    );
  });

  test('размер в тексте загрузки', () {
    expect(forkUploadingText(50 * 1024 * 1024), contains('50'));
  });

  group('partnerWatching', () {
    final now = DateTime(2026, 10, 22, 20);
    WatchVideo v(String by, DateTime at, {bool uploaded = true}) => WatchVideo(
      id: 'x$by${at.millisecondsSinceEpoch}',
      title: 'Фильм',
      url: 'pb://watch_videos/a/b',
      seconds: 0,
      uploaded: uploaded,
      watchingBy: by,
      watchingAt: at.millisecondsSinceEpoch,
    );

    test('видит ролик партнёра, свой не показывает', () {
      expect(partnerWatching([v('me', now)], 'me', now), isNull);
      expect(partnerWatching([v('he', now)], 'me', now)?.watchingBy, 'he');
    });

    test('протухшая и пустая отметка не считаются', () {
      expect(
        partnerWatching(
          [v('he', now.subtract(const Duration(hours: 4)))],
          'me',
          now,
        ),
        isNull,
      );
      expect(partnerWatching([v('', now)], 'me', now), isNull);
      expect(
        partnerWatching([v('he', now, uploaded: false)], 'me', now),
        isNull,
      );
    });
  });
}
