import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/offline/record_scope.dart';
import 'package:love_app/services/offline/scope_sync.dart';

/// RT-1 (аудит 29.10): водяной знак двигался по живым дельтам сокета.
///
/// Сокет рвётся, партнёр в это время пишет — дельта мимо. Сокет вернулся,
/// приходит НОВАЯ дельта и ставит знак на своё `updated`. Следующий запрос к
/// серверу спрашивает `updated > знак`, и записанное за обрыв не приходит
/// больше никогда (до полной сверки, а у списков без неё — вообще).

/// Сервер в памяти: отдаёт записи по условию `updated > "знак"` из фильтра,
/// по возрастанию `updated`, страницами по [perPage].
class _FakeServer {
  _FakeServer({this.perPage = 200});

  final int perPage;
  final records = <RecordModel>[];
  final asked = <String>[];

  static final _wmRe = RegExp(r'updated > "([^"]*)"');

  Future<ResultList<RecordModel>> page(String filter, int page) async {
    asked.add(filter);
    final wm = _wmRe.firstMatch(filter)?.group(1);
    final all =
        records
            .where(
              (r) =>
                  wm == null || (r.data['updated'] as String).compareTo(wm) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (a.data['updated'] as String).compareTo(
              b.data['updated'] as String,
            ),
          );
    final totalPages = all.isEmpty ? 1 : (all.length + perPage - 1) ~/ perPage;
    final from = (page - 1) * perPage;
    final items = from >= all.length
        ? <RecordModel>[]
        : all.sublist(from, (from + perPage).clamp(0, all.length));
    return ResultList<RecordModel>(
      page: page,
      perPage: perPage,
      totalItems: all.length,
      totalPages: totalPages,
      items: items,
    );
  }
}

void main() {
  late LocalStore store;
  late _FakeServer server;
  final outbox = OutboxService.instance;
  const scope = RecordScope('messages:g=g1', equals: {'group_id': 'g1'});

  RecordModel msg(String id, String updated) => RecordModel({
    'id': id,
    'collectionName': 'messages',
    'group_id': 'g1',
    'text': 'текст $id',
    'updated': updated,
  });

  Future<void> sync() => syncScopeIncremental(
    store: store,
    outbox: outbox,
    collection: 'messages',
    token: scope.token,
    baseFilter: 'group_id = "g1"',
    afterWatermark: (wm) => 'updated > "$wm"',
    fetchPage: server.page,
  );

  Future<void> delta(RecordModel r, {String action = 'create'}) =>
      applyLiveDelta(
        store: store,
        outbox: outbox,
        collection: 'messages',
        action: action,
        record: r,
      );

  Future<Set<String>> cached() async =>
      (await store.getScope('messages', scope)).map((r) => r.id).toSet();

  setUp(() async {
    store = LocalStore.instance;
    await store.initWith(databaseFactoryMemory, 'test_watermark.db');
    await store.clearAll();
    server = _FakeServer();
  });

  test(
    'обрыв → пропуск → новая дельта → syncOnce догружает пропущенное',
    () async {
      server.records.add(msg('m1', '2026-10-29 10:00:00.000Z'));
      await sync();
      expect(await cached(), {'m1'});
      expect(await store.lastUpdated(scope.token), '2026-10-29 10:00:00.000Z');

      // Сокет оборван: партнёр пишет, дельта до нас не доходит.
      server.records.add(msg('m2', '2026-10-29 10:05:00.000Z'));

      // Сокет вернулся, приходит свежая дельта.
      final m3 = msg('m3', '2026-10-29 10:10:00.000Z');
      server.records.add(m3);
      await delta(m3);
      expect(await cached(), {'m1', 'm3'});
      expect(
        await store.lastUpdated(scope.token),
        '2026-10-29 10:00:00.000Z',
        reason: 'дельта не двигает водяной знак',
      );

      await sync();
      expect(await cached(), {'m1', 'm2', 'm3'}, reason: 'm2 догружен');
      expect(
        server.asked.last,
        contains('updated > "2026-10-29 10:00:00.000Z"'),
      );
      expect(await store.lastUpdated(scope.token), '2026-10-29 10:10:00.000Z');
    },
  );

  test('знак ставится по максимуму со всех страниц ответа', () async {
    server = _FakeServer(perPage: 2);
    for (var i = 1; i <= 5; i++) {
      server.records.add(msg('m$i', '2026-10-29 10:0$i:00.000Z'));
    }
    await sync();
    expect(await cached(), {'m1', 'm2', 'm3', 'm4', 'm5'});
    expect(await store.lastUpdated(scope.token), '2026-10-29 10:05:00.000Z');

    // Повтор без новых записей знак не трогает и ничего не тянет.
    await sync();
    expect(await store.lastUpdated(scope.token), '2026-10-29 10:05:00.000Z');
  });

  test('удаление дельтой убирает запись и тоже не трогает знак', () async {
    server.records.add(msg('m1', '2026-10-29 10:00:00.000Z'));
    await sync();
    await delta(msg('m1', '2026-10-29 11:00:00.000Z'), action: 'delete');
    expect(await cached(), isEmpty);
    expect(await store.lastUpdated(scope.token), '2026-10-29 10:00:00.000Z');
  });

  test('в lib/ знак не двигается мимо запроса к серверу', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('scope_sync.dart')) continue;
      final src = f.readAsStringSync();
      if (src.contains('setLastUpdated(') || src.contains('bumpWatermark(')) {
        hits.add(f.path);
      }
    }
    // Объявление в local_store.dart — не вызов.
    hits.remove('lib/services/offline/local_store.dart');
    expect(
      hits,
      isEmpty,
      reason:
          'водяной знак ставит только syncScopeIncremental по ответу сервера',
    );
  });
}
