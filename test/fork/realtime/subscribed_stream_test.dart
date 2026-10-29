import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/realtime/subscribed_stream.dart';

/// A7 (аудит RT-5): отмена до конца подписки не оставляет канал и таймер.
void main() {
  group('subscribedStream', () {
    test(
      'отмена до конца подписки: stop сразу, отписка — по готовности',
      () async {
        final pending = Completer<SubscribedUnsub>();
        var unsubs = 0;
        Timer? ticker;
        void Function(int)? emit;

        final stream = subscribedStream<int>(
          start: (add) {
            ticker = Timer.periodic(const Duration(seconds: 2), (_) => add(0));
          },
          subscribe: (add) {
            emit = add;
            return pending.future;
          },
          stop: () => ticker?.cancel(),
        );

        final got = <int>[];
        final sub = stream.listen(got.add);
        await Future<void>.delayed(Duration.zero);
        expect(ticker!.isActive, isTrue);

        final cancelled = sub.cancel();
        expect(ticker!.isActive, isFalse, reason: 'таймер встаёт сразу');
        expect(unsubs, 0);

        pending.complete(() async => unsubs++);
        await cancelled;
        expect(unsubs, 1, reason: 'поздняя подписка снимается');

        emit!(42); // событие из канала после отмены — мимо
        expect(got, isEmpty);
      },
    );

    test('обычный путь: события идут, отмена отписывает один раз', () async {
      var unsubs = 0;
      late void Function(int) emit;
      final stream = subscribedStream<int>(
        subscribe: (add) async {
          emit = add;
          return () async => unsubs++;
        },
      );
      final got = <int>[];
      final sub = stream.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      emit(1);
      emit(2);
      await Future<void>.delayed(Duration.zero);
      expect(got, [1, 2]);
      await sub.cancel();
      expect(unsubs, 1);
    });

    test('ошибка подписки уходит в поток, отмена не падает', () async {
      final stream = subscribedStream<int>(
        subscribe: (_) async => throw StateError('нет сети'),
      );
      final errors = <Object>[];
      final sub = stream.listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<StateError>());
      await sub.cancel();
    });

    test('широковещательный: новый слушатель — новый сеанс', () async {
      var subs = 0;
      var unsubs = 0;
      final stream = subscribedStream<int>(
        broadcast: true,
        subscribe: (_) async {
          subs++;
          return () async => unsubs++;
        },
      );
      // У широковещательного cancel() не ждёт onCancel — ждём очередь.
      await stream.listen((_) {}).cancel();
      await pumpEventQueue();
      await stream.listen((_) {}).cancel();
      await pumpEventQueue();
      expect(subs, 2);
      expect(unsubs, 2);
    });
  });

  test('в lib/ нет ручных async onListen с подпиской на канал', () {
    final offenders = <String>[];
    final onListenAsync = RegExp(r'onListen:\s*\(\)\s*async');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // Комментарии (в т. ч. описание самого рецепта) не считаем.
      final src = f
          .readAsLinesSync()
          .map((l) => l.trimLeft().startsWith('//') ? '' : l)
          .join('\n');
      for (final m in onListenAsync.allMatches(src)) {
        // Тело колбэка грубо — до следующего onCancel или 2000 символов.
        final tail = src.substring(m.end);
        final cut = tail.indexOf('onCancel');
        final body = tail.substring(
          0,
          cut < 0 ? (tail.length < 2000 ? tail.length : 2000) : cut,
        );
        if (RegExp(r'subscribe(Raw|Delta)\(').hasMatch(body)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${f.path.replaceAll('\\', '/')}:$line');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'подписку в потоке поднимай через subscribedStream (RT-5)',
    );
  });
}
