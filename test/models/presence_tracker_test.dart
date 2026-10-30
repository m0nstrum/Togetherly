// B10: присутствие по времени приёма, любому действию и явному уходу.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/presence_liveness.dart';
import 'package:love_app/models/presence_tracker.dart';

void main() {
  var now = 1786650000000;
  late PresenceTracker t;
  setUp(() {
    now = 1786650000000;
    t = PresenceTracker(nowMs: () => now);
  });
  void wait(Duration d) => now += d.inMilliseconds;

  test('услышали — в сети; сорок пять секунд тишины — офлайн', () {
    expect(t.online('bob'), isFalse);
    expect(t.heard('bob'), isTrue, reason: 'приход — повод ответить');
    expect(t.online('bob'), isTrue);
    wait(const Duration(seconds: 30));
    expect(t.online('bob'), isTrue, reason: 'один пропущенный удар не гасит');
    expect(t.heard('bob'), isFalse, reason: 'и так был в сети — не отвечаем');
    wait(PresenceLiveness.freshness);
    expect(t.online('bob'), isFalse);
  });

  test('свежесть по нашим часам: часы партнёра не участвуют', () {
    // Раньше удар нёс `at` отправителя: спешат на секунду — «из будущего»,
    // отстают на минуту — «давно». Трекер этого поля не видит вовсе.
    t.heard('bob');
    expect(t.online('bob'), isTrue);
    expect(t.lastSeen('bob'), now);
  });

  test('отметка базы со спешащих часов всё ещё считается', () {
    expect(t.online('bob', storedSeenMs: now + 1500), isTrue);
    expect(t.online('bob', storedSeenMs: now + 600000), isFalse);
  });

  test(
    '«ушёл» гасит сразу и сильнее отметки базы; новое действие — снова тут',
    () {
      t.heard('bob');
      t.gone('bob');
      expect(t.online('bob', storedSeenMs: now - 1000), isFalse);
      expect(t.lastSeen('bob'), now, reason: 'подпись «была в …» остаётся');
      wait(const Duration(seconds: 2));
      expect(t.heard('bob'), isTrue);
      expect(t.online('bob'), isTrue);
    },
  );

  test('на просьбу ответить — не чаще раза в пять секунд', () {
    expect(t.shouldAnswer(), isTrue);
    expect(t.shouldAnswer(), isFalse);
    wait(PresenceTracker.answerEvery);
    expect(t.shouldAnswer(), isTrue);
  });

  test('clear забывает всех', () {
    t.heard('bob');
    t.clear();
    expect(t.online('bob'), isFalse);
    expect(t.lastSeen('bob'), isNull);
  });
}
