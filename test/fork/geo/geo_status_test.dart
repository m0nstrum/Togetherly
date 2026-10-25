// fork: подписи карты не обещают лишнего (UX G7, G8, G14).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/geo/geo_status.dart';

void main() {
  final now = DateTime(2026, 10, 21, 15, 0);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('pointIsFresh', () {
    test('свежая — до 15 минут', () {
      expect(
        pointIsFresh(
          ms(now.subtract(const Duration(minutes: 5))),
          nowMs: ms(now),
        ),
        isTrue,
      );
      expect(
        pointIsFresh(
          ms(now.subtract(const Duration(minutes: 20))),
          nowMs: ms(now),
        ),
        isFalse,
      );
    });
    test('без времени — не свежая', () {
      expect(pointIsFresh(0, nowMs: ms(now)), isFalse);
    });
  });

  group('partnerPointCaption', () {
    test('свежая точка без подписи', () {
      expect(partnerPointCaption(ms(now), now: now), isNull);
    });
    test('сегодня — время', () {
      final at = DateTime(2026, 10, 21, 9, 5);
      expect(partnerPointCaption(ms(at), now: now), contains('09:05'));
      expect(
        partnerPointCaption(ms(at), now: now),
        isNot(matches(RegExp('вчера|yesterday'))),
      );
    });
    test('вчера и раньше', () {
      final y = DateTime(2026, 10, 20, 23, 40);
      expect(
        partnerPointCaption(ms(y), now: now),
        matches(RegExp('вчера|yesterday')),
      );
      final old = DateTime(2026, 10, 12, 8, 0);
      expect(partnerPointCaption(ms(old), now: now), contains('12.10'));
    });
  });

  group('distanceLabel', () {
    String label(double m, bool fresh) => distanceLabel(
      m,
      fresh: fresh,
      lang: 'ru',
      nearby: 'рядом',
      unitM: 'м',
      unitKm: 'км',
    );
    test('свежие точки — «рядом»', () => expect(label(20, true), 'рядом'));
    test(
      'устаревшие и близко — не «рядом»',
      () => expect(label(20, false), matches(RegExp('до 50|under 50'))),
    );
    test('устаревшие и далеко — обычное расстояние', () {
      expect(label(2900, false), label(2900, true));
    });
  });

  group('ShareIssue', () {
    test('у каждой причины есть текст, кроме none', () {
      for (final i in ShareIssue.values) {
        expect(i.text == null, i == ShareIssue.none, reason: '$i');
      }
    });
    test('кнопка настроек — только там, где это лечится', () {
      expect(ShareIssue.deniedForever.actionLabel, isNotNull);
      expect(ShareIssue.servicesOff.needsLocationSettings, isTrue);
      expect(ShareIssue.noPartner.actionLabel, isNull);
    });
  });

  test('подсказка ожидания зависит от того, делится ли человек сам', () {
    expect(
      waitingPartnerHint(iShare: true),
      isNot(waitingPartnerHint(iShare: false)),
    );
  });
}
