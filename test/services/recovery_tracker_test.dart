// A11: каналы `pair:`/`user:` держат историю в Centrifugo. После обрыва
// подписка восстанавливается из неё, и перечитывать списки запросами не нужно;
// recovered=false, ошибка подписки или молчание — догон, как раньше.
//
// Что публикации действительно приходят из истории на настоящем Centrifugo с
// боевым конфигом — server/scripts/realtime-broker.test.cjs.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/services/recovery_tracker.dart';
import 'package:love_app/services/sync_coordinator.dart';

void main() {
  group('RecoveryTracker', () {
    test('история есть у pair: и user:, у остальных — нет', () {
      expect(RecoveryTracker.recoverable('pair:g1'), isTrue);
      expect(RecoveryTracker.recoverable('user:u1'), isTrue);
      for (final c in ['draw:g1', 'watch:g1', 'loc:x', 'signal:g1']) {
        expect(RecoveryTracker.recoverable(c), isFalse, reason: c);
      }
    });

    test('восстановилась — догона нет; не восстановилась — догон', () {
      fakeAsync((async) {
        final t = RecoveryTracker();
        final gaps = <String>[];
        t.gaps.listen(gaps.add);
        t.dropped();
        t.reconnected(['pair:g1', 'user:u1']);
        t.subscribed('pair:g1', recovered: true);
        t.subscribed('user:u1', recovered: false);
        async.elapse(const Duration(seconds: 30));
        expect(gaps, ['user:u1']);
      });
    });

    test('ошибка подписки — догон сразу', () {
      fakeAsync((async) {
        final t = RecoveryTracker();
        final gaps = <String>[];
        t.gaps.listen(gaps.add);
        t.reconnected(['pair:g1']);
        t.failed('pair:g1');
        async.flushMicrotasks();
        expect(gaps, ['pair:g1']);
        // Повторная ошибка того же переподключения второго догона не даёт.
        t.failed('pair:g1');
        async.elapse(const Duration(seconds: 30));
        expect(gaps, ['pair:g1']);
      });
    });

    test('подписка молчит — догон по таймауту', () {
      fakeAsync((async) {
        final t = RecoveryTracker(timeout: const Duration(seconds: 10));
        final gaps = <String>[];
        t.gaps.listen(gaps.add);
        t.reconnected(['pair:g1']);
        async.elapse(const Duration(seconds: 9));
        expect(gaps, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(gaps, ['pair:g1']);
      });
    });

    test('ответ подписки раньше сигнала «переподключились» не теряется', () {
      fakeAsync((async) {
        final t = RecoveryTracker();
        final gaps = <String>[];
        t.gaps.listen(gaps.add);
        t.dropped();
        t.subscribed('pair:g1', recovered: true);
        t.reconnected(['pair:g1']);
        async.elapse(const Duration(seconds: 30));
        expect(gaps, isEmpty);
        // Следующий обрыв прошлое восстановление не засчитывает.
        t.dropped();
        t.reconnected(['pair:g1']);
        async.elapse(const Duration(seconds: 30));
        expect(gaps, ['pair:g1']);
      });
    });

    test('каналы без истории не ждут', () {
      fakeAsync((async) {
        final t = RecoveryTracker();
        final gaps = <String>[];
        t.gaps.listen(gaps.add);
        t.reconnected(['draw:g1', 'signal:g1']);
        async.elapse(const Duration(seconds: 30));
        expect(gaps, isEmpty);
      });
    });
  });

  group('SyncCoordinator с историей', () {
    late StreamController<void> reconnected;
    late RecoveryTracker tracker;
    late SyncCoordinator coordinator;

    setUp(() {
      reconnected = StreamController<void>.broadcast();
      tracker = RecoveryTracker();
      coordinator = SyncCoordinator(
        reconnected: reconnected.stream,
        foreground: const Stream<bool>.empty(),
        keyRecovered: const Stream<String>.empty(),
        isSubscribed: (_) => true,
        unrecovered: tracker.gaps,
        minInterval: Duration.zero,
        jitter: () => Duration.zero,
      );
    });

    /// Обрыв → переподключение → ответ подписки [channel].
    void drop(FakeAsync async, String channel, {required bool recovered}) {
      tracker.dropped();
      tracker.reconnected([channel]);
      reconnected.add(null);
      async.flushMicrotasks();
      tracker.subscribed(channel, recovered: recovered);
      async.elapse(const Duration(seconds: 30));
    }

    test('обрыв → публикации пришли из истории → без syncOnce', () {
      fakeAsync((async) {
        var syncs = 0;
        coordinator.register(channel: 'pair:g1', sync: () async => syncs++);
        drop(async, 'pair:g1', recovered: true);
        expect(syncs, 0);
      });
    });

    test('обрыв → recovered=false → syncOnce, как раньше', () {
      fakeAsync((async) {
        var syncs = 0;
        coordinator.register(channel: 'pair:g1', sync: () async => syncs++);
        drop(async, 'pair:g1', recovered: false);
        expect(syncs, 1);
      });
    });

    test('каналы без истории и области без канала — по reconnected', () {
      fakeAsync((async) {
        var draw = 0, plain = 0;
        coordinator.register(channel: 'draw:g1', sync: () async => draw++);
        coordinator.register(sync: () async => plain++);
        drop(async, 'pair:g1', recovered: true);
        expect(draw, 1);
        expect(plain, 1);
      });
    });
  });
}
