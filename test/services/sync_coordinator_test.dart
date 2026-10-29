// RT-2/RT-3 (аудит 29.10): догон после переподключения сокета, возврата из
// фона и возвращения ключа подписи сервера был только у чата и дома питомца.
// Воспоминания, настроения, желания, подарки и остальное ждали смены сети
// устройства, и изменение партнёра, случившееся в разрыв, не появлялось.
//
// Здесь — правило координатора на настоящем кэше и инкрементальной
// синхронизации; подключение областей к нему — sync_coordinator_wiring_test.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';
import 'package:love_app/services/offline/record_scope.dart';
import 'package:love_app/services/offline/scope_sync.dart';
import 'package:love_app/services/sync_coordinator.dart';

/// Сервер в памяти: отдаёт записи по условию `updated > "знак"` из фильтра.
class _FakeServer {
  final records = <RecordModel>[];
  int asked = 0;

  static final _wmRe = RegExp(r'updated > "([^"]*)"');

  Future<ResultList<RecordModel>> page(String filter, int page) async {
    asked++;
    final wm = _wmRe.firstMatch(filter)?.group(1);
    final items =
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
    return ResultList<RecordModel>(
      page: page,
      perPage: 200,
      totalItems: items.length,
      totalPages: 1,
      items: items,
    );
  }
}

class _Signals {
  final reconnected = StreamController<void>.broadcast();
  final foreground = StreamController<bool>.broadcast();
  final keyRecovered = StreamController<String>.broadcast();
  bool subscribed = true;
  DateTime clock = DateTime(2026, 10, 29, 12);

  SyncCoordinator coordinator({
    Duration jitter = Duration.zero,
    Duration minInterval = const Duration(seconds: 3),
    DateTime Function()? now,
  }) => SyncCoordinator(
    reconnected: reconnected.stream,
    foreground: foreground.stream,
    keyRecovered: keyRecovered.stream,
    isSubscribed: (_) => subscribed,
    minInterval: minInterval,
    jitter: () => jitter,
    now: now ?? () => clock,
  );
}

void main() {
  group('догон области на кэше', () {
    late LocalStore store;
    late _FakeServer server;
    late _Signals signals;
    final outbox = OutboxService.instance;
    const scope = RecordScope('memories:g=g1', equals: {'group_id': 'g1'});

    RecordModel memory(String id, String updated) => RecordModel({
      'id': id,
      'collectionName': 'memories',
      'group_id': 'g1',
      'updated': updated,
    });

    Future<Set<String>> cached() async =>
        (await store.getScope('memories', scope)).map((r) => r.id).toSet();

    /// Регистрирует область, как `_watchCached`, и отдаёт счётчик догонов.
    ({SyncHandle handle, List<Completer<void>> runs}) register(
      SyncCoordinator c, {
      String channel = 'pair:g1',
    }) {
      final runs = <Completer<void>>[Completer<void>()];
      final handle = c.register(
        channel: channel,
        sync: () async {
          await syncScopeIncremental(
            store: store,
            outbox: outbox,
            collection: 'memories',
            token: scope.token,
            baseFilter: 'group_id = "g1"',
            afterWatermark: (wm) => 'updated > "$wm"',
            fetchPage: server.page,
          );
          runs.last.complete();
          runs.add(Completer<void>());
        },
      );
      return (handle: handle, runs: runs);
    }

    setUp(() async {
      store = LocalStore.instance;
      await store.initWith(databaseFactoryMemory, 'test_sync_coordinator.db');
      await store.clearAll();
      server = _FakeServer();
      signals = _Signals();
      // Область уже загружена: m1 в кэше, знак на нём.
      server.records.add(memory('m1', '2026-10-29 10:00:00.000Z'));
      await syncScopeIncremental(
        store: store,
        outbox: outbox,
        collection: 'memories',
        token: scope.token,
        baseFilter: 'group_id = "g1"',
        afterWatermark: (wm) => 'updated > "$wm"',
        fetchPage: server.page,
      );
    });

    test('обрыв сокета → запись пропущена → reconnected → область догнана',
        () async {
      final c = signals.coordinator();
      final r = register(c);
      // Сокет оборван: партнёр добавил воспоминание, дельта до нас не дошла.
      server.records.add(memory('m2', '2026-10-29 10:05:00.000Z'));
      expect(await cached(), {'m1'});

      signals.reconnected.add(null);
      await r.runs.first.future.timeout(const Duration(seconds: 5));
      expect(await cached(), {'m1', 'm2'}, reason: 'm2 догнан по reconnected');
      r.handle.dispose();
    });

    test('resumed после фона догоняет область', () async {
      final c = signals.coordinator();
      final r = register(c);
      signals.foreground.add(false);
      await pumpEventQueue();
      server.records.add(memory('m2', '2026-10-29 10:05:00.000Z'));
      signals.clock = signals.clock.add(const Duration(minutes: 5));
      signals.foreground.add(true);
      await r.runs.first.future.timeout(const Duration(seconds: 5));
      expect(await cached(), {'m1', 'm2'});
      r.handle.dispose();
    });

    test('ключ подписи появился → догон областей этого канала', () async {
      final c = signals.coordinator();
      final mine = register(c);
      var otherRuns = 0;
      final other = c.register(
        channel: 'pair:g2',
        sync: () async => otherRuns++,
      );
      // Без ключа дельта m2 отброшена (fail closed), ключ вернулся.
      server.records.add(memory('m2', '2026-10-29 10:05:00.000Z'));
      signals.keyRecovered.add('pair:g1');
      await mine.runs.first.future.timeout(const Duration(seconds: 5));
      expect(await cached(), {'m1', 'm2'});
      expect(otherRuns, 0, reason: 'у чужого канала дельты не терялись');
      mine.handle.dispose();
      other.dispose();
    });
  });

  test('шторм переподключений → не больше N догонов, последний — после '
      'последнего повода', () {
    fakeAsync((async) {
      final signals = _Signals();
      final clock = async.getClock(DateTime(2026, 10, 29, 12));
      final c = signals.coordinator(
        jitter: const Duration(milliseconds: 500),
        now: clock.now,
      );
      final starts = <DateTime>[];
      final handle = c.register(
        channel: 'pair:g1',
        sync: () async {
          starts.add(clock.now());
          // Ответ сервера идёт секунду.
          await Future<void>.delayed(const Duration(seconds: 1));
        },
      );
      // Сокет моргает каждые 100 мс в течение 10 секунд.
      DateTime? lastReconnect;
      for (var i = 0; i < 100; i++) {
        signals.reconnected.add(null);
        lastReconnect = clock.now();
        async.elapse(const Duration(milliseconds: 100));
      }
      async.elapse(const Duration(seconds: 30));
      // Окно 3 с на 10 с шторма: не больше пяти запросов вместо ста.
      expect(starts.length, inInclusiveRange(2, 5));
      expect(
        starts.last.isAfter(lastReconnect!),
        isTrue,
        reason: 'пропущенное за последний обрыв тоже догнано',
      );
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          greaterThanOrEqualTo(const Duration(seconds: 3)),
        );
      }
      handle.dispose();
    });
  });

  test('без подписки на канал область не опрашивается, если не просили', () {
    fakeAsync((async) {
      final signals = _Signals()..subscribed = false;
      final c = signals.coordinator();
      var plain = 0, chat = 0;
      final a = c.register(channel: 'pair:g1', sync: () async => plain++);
      final b = c.register(
        channel: 'pair:g1',
        sync: () async => chat++,
        pollWithoutSocket: true,
      );
      async.elapse(const Duration(seconds: 31));
      expect(plain, 0);
      expect(chat, 2);
      a.dispose();
      b.dispose();
    });
  });

  test('снятая область больше не догоняется', () {
    fakeAsync((async) {
      final signals = _Signals();
      final c = signals.coordinator();
      var runs = 0;
      final handle = c.register(channel: 'pair:g1', sync: () async => runs++);
      expect(c.activeScopes, 1);
      handle
        ..dispose()
        ..dispose();
      expect(c.activeScopes, 0);
      signals.reconnected.add(null);
      signals.keyRecovered.add('pair:g1');
      async.elapse(const Duration(seconds: 10));
      expect(runs, 0);
    });
  });
}
