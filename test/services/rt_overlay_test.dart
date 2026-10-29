import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/offline/record_scope.dart';
import 'package:love_app/services/offline/scope_sync.dart';
import 'package:love_app/services/rt_overlay.dart';

/// RT-4 (аудит 29.10): список сначала загружался, потом подписывался —
/// изменение партнёра между ответом сервера и подпиской терялось навсегда.
/// Теперь подписка ставится до загрузки, дельты копятся и ложатся поверх
/// снимка, не откатывая в нём ничего более свежего.
RecordModel rec(String id, String updated, {String text = ''}) => RecordModel({
  'id': id,
  'group_id': 'g1',
  'text': text.isEmpty ? 'текст $id' : text,
  'updated': updated,
});

void main() {
  group('in-memory список', () {
    test('дельта между загрузкой и подпиской не теряется', () {
      // Снимок сервера снят в 10:00; пока ответ летел, партнёр создал m2 и
      // поправил m1 — дельты легли в буфер подписки.
      final byId = {'m1': rec('m1', '2026-10-29 10:00:00.000Z')};
      overlayDeltas(byId, [
        (action: 'create', record: rec('m2', '2026-10-29 10:00:01.000Z')),
        (
          action: 'update',
          record: rec('m1', '2026-10-29 10:00:02.000Z', text: 'поправлено'),
        ),
      ]);
      expect(byId.keys, unorderedEquals(['m1', 'm2']));
      expect(byId['m1']!.data['text'], 'поправлено');
    });

    test('дельта старее снимка его не откатывает', () {
      final byId = {
        'm1': rec('m1', '2026-10-29 10:05:00.000Z', text: 'свежее'),
      };
      overlayDeltas(byId, [
        (
          action: 'update',
          record: rec('m1', '2026-10-29 10:00:00.000Z', text: 'старое'),
        ),
        (action: 'delete', record: rec('m1', '2026-10-29 10:00:00.000Z')),
      ]);
      expect(byId['m1']!.data['text'], 'свежее');
    });

    test('удаление во время загрузки убирает запись из снимка', () {
      final byId = {'m1': rec('m1', '2026-10-29 10:00:00.000Z')};
      overlayDeltas(byId, [
        (action: 'delete', record: rec('m1', '2026-10-29 10:00:00.000Z')),
      ]);
      expect(byId, isEmpty);
    });

    test('документ: побеждает более свежая версия', () {
      final loaded = rec('d', '2026-10-29 10:00:00.000Z', text: 'ответ');
      final newer = rec('d', '2026-10-29 10:00:01.000Z', text: 'дельта');
      expect(
        pickFresher(
          loaded: loaded,
          delta: (action: 'update', record: newer),
        ).record!.data['text'],
        'дельта',
      );
      expect(
        pickFresher(
          loaded: newer,
          delta: (action: 'update', record: loaded),
        ).record!.data['text'],
        'дельта',
      );
      expect(
        pickFresher(
          loaded: null,
          delta: (action: 'create', record: newer),
        ).gone,
        isFalse,
        reason: 'getOne ответил 404, а запись успели создать',
      );
    });
  });

  test('догоны по одному: второй не идёт вперехлёст, а следом', () async {
    var running = 0;
    var maxRunning = 0;
    var runs = 0;
    final gates = <Completer<void>>[];
    final refetch = singleFlight(() async {
      running++;
      runs++;
      if (running > maxRunning) maxRunning = running;
      final c = Completer<void>();
      gates.add(c);
      await c.future;
      running--;
    });
    final a = refetch();
    final b = refetch();
    final c = refetch();
    await Future<void>.delayed(Duration.zero);
    gates.first.complete();
    await Future<void>.delayed(Duration.zero);
    while (gates.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    gates[1].complete();
    await Future.wait([a, b, c]);
    expect(maxRunning, 1);
    expect(runs, 2, reason: 'сколько бы ни просили во время прохода — один');
  });

  group('кэш-список', () {
    late LocalStore store;
    final outbox = OutboxService.instance;
    const scope = RecordScope('m:g=g1', equals: {'group_id': 'g1'});

    setUp(() async {
      store = LocalStore.instance;
      await store.initWith(databaseFactoryMemory, 'test_rt_overlay.db');
      await store.clearAll();
      await outbox.clear();
    });

    Future<String?> text(String id) async =>
        (await store.getRecord('m', id))?.data['text'] as String?;

    test('страница синхронизации не откатывает дельту новее неё', () async {
      // Подписка уже стоит: пока страница летела, пришла свежая дельта.
      await applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'm',
        action: 'update',
        record: rec('m1', '2026-10-29 10:05:00.000Z', text: 'свежее'),
      );
      await syncScopeIncremental(
        store: store,
        outbox: outbox,
        collection: 'm',
        token: scope.token,
        baseFilter: '',
        afterWatermark: (wm) => 'updated > "$wm"',
        fetchPage: (filter, page) async => ResultList<RecordModel>(
          page: 1,
          perPage: 200,
          totalItems: 1,
          totalPages: 1,
          items: [rec('m1', '2026-10-29 10:00:00.000Z', text: 'старое')],
        ),
      );
      expect(await text('m1'), 'свежее');
    });

    test('запоздавшая дельта не откатывает кэш', () async {
      await applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'm',
        action: 'update',
        record: rec('m1', '2026-10-29 10:05:00.000Z', text: 'свежее'),
      );
      await applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'm',
        action: 'update',
        record: rec('m1', '2026-10-29 10:00:00.000Z', text: 'старое'),
      );
      expect(await text('m1'), 'свежее');
    });
  });
}
