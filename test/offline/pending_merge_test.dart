import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/offline/pending_merge.dart';
import 'package:love_app/services/offline/scope_sync.dart';

/// RT-6 (аудит 29.10): дельта партнёра по записи со своей неотправленной
/// правкой выбрасывалась целиком, а после отправки своя версия перезаписывала
/// серверную. Теперь дельта сливается по полям: поля своей правки остаются
/// своими, остальное — партнёрское.
void main() {
  late LocalStore store;
  final outbox = OutboxService.instance;
  late Completer<void> gate;

  Future<void> waitPending(String col, String id, bool want) async {
    for (var i = 0; i < 200; i++) {
      if (outbox.isPending(col, id) == want) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('isPending($col/$id) так и не стало $want');
  }

  Future<Map<String, dynamic>> cached(String col, String id) async =>
      (await store.getRecord(col, id))!.toJson();

  setUp(() async {
    store = LocalStore.instance;
    await store.initWith(databaseFactoryMemory, 'test_pending_merge.db');
    await store.clearAll();
    await outbox.clear();
    gate = Completer<void>();
    // Операция висит «в сети», пока тест не отпустит: запись остаётся pending.
    outbox.applyOverride = (type, payload) async {
      await gate.future;
      return true;
    };
  });

  tearDown(() async {
    if (!gate.isCompleted) gate.complete();
    outbox.applyOverride = null;
    await outbox.clear();
  });

  test(
    'правка партнёра в другом поле при своей pending — обе сохранились',
    () async {
      await store.upsertRaw('wishes', 'w1', {
        'id': 'w1',
        'title': 'Велосипед',
        'done': false,
        'pos': 'a',
        'updated': '2026-10-29 10:00:00.000Z',
      });
      // Своя правка: переставил желание — оптимистично в кэш и в очередь.
      await store.patchRecordFields('wishes', 'w1', {'pos': 'z'});
      await outbox.enqueue('wishMark', {
        'id': 'w1',
        'fields': {'pos': 'z'},
      });
      await waitPending('wishes', 'w1', true);

      // Партнёр в это время отметил желание сбывшимся.
      final deferred = <String>[];
      await applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'wishes',
        action: 'update',
        record: RecordModel({
          'id': 'w1',
          'title': 'Велосипед',
          'done': true,
          'pos': 'a',
          'updated': '2026-10-29 10:01:00.000Z',
        }),
        onDeferred: deferred.add,
      );

      final rec = await cached('wishes', 'w1');
      expect(rec['done'], true, reason: 'отметка партнёра не потерялась');
      expect(rec['pos'], 'z', reason: 'своя неотправленная правка цела');
      expect(deferred, ['w1'], reason: 'после отправки запись перечитаем');

      // Отправка ушла — очередь сообщает, что запись можно перечитать.
      final settled = outbox.settled.first;
      gate.complete();
      expect(await settled, contains('wishes:w1'));
    },
  );

  test(
    'memories.data: реакция партнёра и своя наклейка — обе на месте',
    () async {
      await store.upsertRaw('memories', 'm1', {
        'id': 'm1',
        'data': {
          'text': 'Море',
          'reactions': {'me': '❤️'},
          'stickers': {
            's1': {'k': 'star'},
          },
        },
        'updated': '2026-10-29 10:00:00.000Z',
      });
      await outbox.enqueue('memorySticker', {
        'memoryId': 'm1',
        'sid': 's1',
        'del': true,
      });
      // Оптимистично наклейку уже убрали.
      await store.upsertRaw('memories', 'm1', {
        'id': 'm1',
        'data': {
          'text': 'Море',
          'reactions': {'me': '❤️'},
          'stickers': <String, dynamic>{},
        },
        'updated': '2026-10-29 10:00:00.000Z',
      });
      await waitPending('memories', 'm1', true);

      await applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'memories',
        action: 'update',
        record: RecordModel({
          'id': 'm1',
          'data': {
            'text': 'Море',
            'reactions': {'me': '❤️', 'partner': '😂'},
            'stickers': {
              's1': {'k': 'star'},
            },
          },
          'updated': '2026-10-29 10:02:00.000Z',
        }),
      );

      final data = (await cached('memories', 'm1'))['data'] as Map;
      expect(data['reactions'], {'me': '❤️', 'partner': '😂'});
      expect(data['stickers'], isEmpty, reason: 'своё удаление наклейки цело');
    },
  );

  test('правка всей записи: кэш свой, запись отложена до отправки', () async {
    await store.upsertRaw('memories', 'm2', {
      'id': 'm2',
      'data': {'text': 'моя версия'},
    });
    await outbox.enqueue('memoryUpsert', {
      'id': 'm2',
      'groupId': 'g',
      'data': {'text': 'моя версия'},
    });
    await waitPending('memories', 'm2', true);

    final deferred = <String>[];
    await applyLiveDelta(
      store: store,
      outbox: outbox,
      collection: 'memories',
      action: 'update',
      record: RecordModel({
        'id': 'm2',
        'data': {'text': 'версия партнёра'},
        'updated': '2026-10-29 10:03:00.000Z',
      }),
      onDeferred: deferred.add,
    );
    expect(
      ((await cached('memories', 'm2'))['data'] as Map)['text'],
      'моя версия',
    );
    expect(deferred, ['m2']);

    // После отправки запись перечитывается и кэш берёт серверную версию.
    gate.complete();
    await waitPending('memories', 'm2', false);
    await refetchSettled(
      store: store,
      outbox: outbox,
      collection: 'memories',
      id: 'm2',
      fetch: (id) async => RecordModel({
        'id': id,
        'data': {'text': 'на сервере'},
        'updated': '2026-10-29 10:04:00.000Z',
      }),
    );
    expect(
      ((await cached('memories', 'm2'))['data'] as Map)['text'],
      'на сервере',
    );
  });

  group('mergeOverPending', () {
    test('словарь участника: свой ключ свой, чужие — серверные', () {
      final m = mergeOverPending(
        server: {
          'id': 'g',
          'member_moods': {'me': 'old', 'partner': 'new'},
          'current_status': 'srv',
        },
        local: {
          'id': 'g',
          'member_moods': {'me': 'mine', 'partner': 'old'},
          'current_status': 'loc',
        },
        ops: [
          (type: 'groupSetMemberMood', payload: {'groupId': 'g', 'uid': 'me'}),
        ],
      ).merged!;
      expect(m['member_moods'], {'me': 'mine', 'partner': 'new'});
      expect(m['current_status'], 'srv');
    });

    test('своя правка удалила ключ — сервер его не возвращает', () {
      final m = mergeOverPending(
        server: {
          'id': 'c',
          'reactions': {'me': '👍', 'partner': '🔥'},
        },
        local: {'id': 'c', 'reactions': <String, dynamic>{}},
        ops: [
          (type: 'chatSetReaction', payload: {'id': 'c', 'uid': 'me'}),
        ],
      ).merged!;
      expect(m['reactions'], {'partner': '🔥'});
    });

    test('неизвестная операция — слияния нет', () {
      expect(
        mergeOverPending(
          server: {'id': 'x'},
          local: {'id': 'x'},
          ops: [(type: 'wishUpsert', payload: const {})],
        ).merged,
        isNull,
      );
    });
  });
}
