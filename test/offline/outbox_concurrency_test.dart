import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';

/// Аудит B-1, B-2, B-3: очередь не должна слать одну операцию дважды и не
/// должна вечно крутить то, что сервер отверг навсегда.
void main() {
  final box = OutboxService.instance;
  final pending = intMapStoreFactory.store('outbox');
  final poison = intMapStoreFactory.store('outbox_poison');
  late Database db;

  setUp(() async {
    await LocalStore.instance.initWith(
      databaseFactoryMemory,
      'outbox-concurrency.db',
    );
    await box.clear();
    db = (await LocalStore.instance.database())!;
  });

  tearDown(() async {
    box.applyOverride = null;
    box.timeoutOverride = null;
    box.clock = DateTime.now;
    await box.dispose();
    await box.clear();
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('два flush подряд шлют каждую операцию один раз (B-1)', () async {
    await pending.add(db, {
      'type': 'counterInc',
      'payload': {'groupId': 'g', 'field': 'hugs', 'by': 1},
      'attempts': 0,
    });
    await pending.add(db, {
      'type': 'memoryBumpComments',
      'payload': {'groupId': 'g', 'memoryId': 'm', 'by': 1},
      'attempts': 0,
    });
    await pending.add(db, {
      'type': 'chatUpsert',
      'payload': {'id': 'c', 'groupId': 'g'},
      'attempts': 0,
    });
    final applied = <String>[];
    box.applyOverride = (type, _) async {
      applied.add(type);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return true;
    };

    // Без await между вызовами — как enqueue и повтор по сети в один кадр.
    final a = box.flush();
    final b = box.flush();
    await Future.wait([a, b]);
    await until(() => box.pendingCount.value == 0);

    expect(applied.where((t) => t == 'counterInc'), hasLength(1));
    expect(applied.where((t) => t == 'memoryBumpComments'), hasLength(1));
    expect(applied, hasLength(3));
    expect(await pending.count(db), 0);
  });

  test(
    'операция после таймаута не стартует второй раз, пока идёт первая (B-2)',
    () async {
      box.timeoutOverride = (_) => const Duration(milliseconds: 20);
      final gate = Completer<bool>();
      var runs = 0;
      box.applyOverride = (_, _) {
        runs++;
        return gate.future;
      };
      await pending.add(db, {
        'type': 'counterInc',
        'payload': {'groupId': 'g', 'field': 'hugs', 'by': 1},
        'attempts': 0,
      });

      await box.flush(); // ушла в таймаут, но работа продолжается
      expect(runs, 1);
      await box.flush(); // повторный проход — второй запуск запрещён
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(runs, 1);
      expect(await pending.count(db), 1);

      gate.complete(true); // исходный запрос всё-таки доехал
      await until(() => box.pendingCount.value == 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runs, 1);
      expect(await pending.count(db), 0);
    },
  );

  test('хвост таймаута провалился — операцию шлют заново', () async {
    box.timeoutOverride = (_) => const Duration(milliseconds: 20);
    final gate = Completer<bool>();
    var runs = 0;
    box.applyOverride = (_, _) {
      runs++;
      return runs == 1 ? gate.future : Future.value(true);
    };
    await pending.add(db, {
      'type': 'chatUpsert',
      'payload': {'id': 'c', 'groupId': 'g'},
      'attempts': 0,
    });

    await box.flush();
    gate.complete(false);
    await until(() => box.pendingCount.value == 0);
    expect(runs, 2);
    expect(await pending.count(db), 0);
  });

  group('авто-повтор отравленных (B-3)', () {
    late StreamController<void> reconnected;
    late StreamController<bool> online;
    var now = DateTime(2026, 10, 29, 12);

    setUp(() async {
      online = StreamController<bool>.broadcast();
      reconnected = StreamController<void>.broadcast();
      now = DateTime(2026, 10, 29, 12);
      box.clock = () => now;
    });

    // Подписки — в теле теста, а не в setUp: слив, запущенный из них, живёт
    // в зоне подписчика, и ошибки операций иначе вылетали бы мимо теста.
    Future<void> start() =>
        box.init(onlineChanges: online.stream, reconnected: reconnected.stream);

    tearDown(() async {
      await online.close();
      await reconnected.close();
    });

    Future<void> seedPoison(int status) => poison
        .add(db, {
          'type': 'chatUpsert',
          'payload': {'id': 'x', 'groupId': 'g'},
          'attempts': 5,
          'failedAt': now.toIso8601String(),
          'status': status,
        })
        .then((_) {});

    Future<void> reconnect() async {
      reconnected.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await until(() => box.pendingCount.value == 0);
    }

    test(
      'постоянный 4xx не крутится вечно, кнопка всё равно повторяет',
      () async {
        await seedPoison(400);
        var runs = 0;
        box.applyOverride = (_, _) async {
          runs++;
          throw ClientException(statusCode: 400);
        };
        await start();

        // Сотня переподключений подряд — ни одного запроса: пауза не вышла.
        for (var i = 0; i < 100; i++) {
          reconnected.add(null);
        }
        await reconnect();
        expect(runs, 0);

        // Сутки дёргающейся сети: повторов не больше лимита, по одной попытке.
        for (var i = 0; i < 48; i++) {
          now = now.add(const Duration(minutes: 30));
          await reconnect();
          online.add(true);
          await reconnect();
        }
        expect(runs, 3);
        expect(await poison.count(db), 1);
        expect(await pending.count(db), 0);

        // Явное действие человека повторяет всегда.
        await box.retryPoison();
        await until(() => runs == 4);
        expect(runs, 4);
      },
    );

    test('401 после перелогина проходит и после лимита', () async {
      await seedPoison(401);
      var accepted = false;
      var runs = 0;
      box.applyOverride = (_, _) async {
        runs++;
        if (accepted) return true;
        throw ClientException(statusCode: 401);
      };
      await start();
      for (var i = 0; i < 5; i++) {
        now = now.add(const Duration(minutes: 2));
        await reconnect();
      }
      expect(runs, 5);
      expect(await poison.count(db), 1);

      accepted = true; // человек перелогинился, сокет переподключился
      now = now.add(const Duration(minutes: 2));
      await reconnect();
      expect(await poison.count(db), 0);
      expect(await pending.count(db), 0);
    });

    test(
      'переподключение по-прежнему досылает очередь после сбоя сети',
      () async {
        await pending.add(db, {
          'type': 'chatUpsert',
          'payload': {'id': 'y', 'groupId': 'g'},
          'attempts': 7,
        });
        box.applyOverride = (_, _) async => true;
        await start();
        await reconnect();
        expect(await pending.count(db), 0);
      },
    );
  });
}
