import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/video_ux.dart';

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
}
