import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/realtime/verified_delta.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fork/realtime/fixtures/signed_delta.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final packet = Map<String, dynamic>.from(fixture['envelope'] as Map);
  const channel = 'pair:pairaaaaaaaaaaa';
  PocketBase backend({bool unavailable = false, int offset = 0}) => PocketBase(
    'https://example.test',
    httpClientFactory: () => MockClient((request) async {
      expect(request.url.path, '/api/fork/realtime-key');
      return unavailable
          ? http.Response('{}', 503)
          : http.Response(
              jsonEncode({
                'v': 1,
                'alg': 'Ed25519',
                'key': fixture['key'],
                'time': (packet['at'] as int) + offset,
              }),
              200,
            );
    }),
  );
  ForkVerifiedDelta verifier({int offset = 0, bool unavailable = false}) =>
      ForkVerifiedDelta(backend(unavailable: unavailable, offset: offset));

  test(
    'valid signature uses HTTPS server time and permits a delta exactly once',
    () async {
      final v = verifier();
      final results = await Future.wait([
        v.open(channel, packet),
        v.open(channel, packet),
      ]);
      expect(results.whereType<Map<String, dynamic>>(), hasLength(1));
      expect(
        results.whereType<Map<String, dynamic>>().single['event'],
        'delete',
      );
      expect(await v.open(channel, packet), isNull);
    },
  );
  test(
    'unsigned, modified, cross-channel, old and future packets are rejected',
    () async {
      expect(
        await verifier().open(channel, {
          'event': 'delete',
          'collection': 'groups',
          'record': {'id': 'pair'},
        }),
        isNull,
      );
      expect(await verifier().open('pair:other', packet), isNull);
      for (final patch in <Map<String, dynamic>>[
        {'payload': 'e30'},
        {'at': (packet['at'] as int) + 1},
        {'nonce': 'f' * 32},
        {'sig': 'a' * 86},
        {'sig': null},
        {'v': 2},
        {'at': 1.5},
        {'payload': 'a' * (16 << 20) + 'x'},
      ]) {
        expect(
          await verifier().open(channel, {...packet, ...patch}),
          isNull,
          reason: '${patch.keys}',
        );
      }
      expect(await verifier(offset: 600001).open(channel, packet), isNull);
      expect(await verifier(offset: -30001).open(channel, packet), isNull);
      expect(await verifier(unavailable: true).open(channel, packet), isNull);
    },
  );
  test(
    'client signals use separate namespaces without changing logical AAD',
    () {
      expect(
        ForkVerifiedDelta.signalChannel(channel),
        'signal:pairaaaaaaaaaaa',
      );
      expect(
        ForkVerifiedDelta.signalChannel('loc:pair_a_b'),
        'locsignal:pair_a_b',
      );
      expect(ForkVerifiedDelta.signalChannel('draw:g'), 'draw:g');
      expect(ForkVerifiedDelta.signalChannel('watch:g'), 'watch:g');
      expect(ForkVerifiedDelta.signalChannel('user:a'), 'user:a');
    },
  );
  test(
    'reconnect retries an unavailable key without an unsigned fallback',
    () async {
      var available = false;
      final pb = PocketBase(
        'https://example.test',
        httpClientFactory: () => MockClient(
          (_) async => available
              ? http.Response(
                  jsonEncode({
                    'v': 1,
                    'alg': 'Ed25519',
                    'key': fixture['key'],
                    'time': packet['at'],
                  }),
                  200,
                )
              : http.Response('{}', 503),
        ),
      );
      final v = ForkVerifiedDelta(pb);
      expect(await v.open(channel, packet), isNull);
      available = true;
      v.refreshKey();
      expect((await v.open(channel, packet))?['event'], 'delete');
    },
  );

  // RT-3: дельта без ключа отбрасывается (fail closed), но канал надо догнать,
  // когда ключ вернётся, — иначе пропуск живёт до смены сети.
  PocketBase toggled(bool Function() available) => PocketBase(
    'https://example.test',
    httpClientFactory: () => MockClient(
      (_) async => available()
          ? http.Response(
              jsonEncode({
                'v': 1,
                'alg': 'Ed25519',
                'key': fixture['key'],
                'time': packet['at'],
              }),
              200,
            )
          : http.Response('{}', 503),
    ),
  );

  test('ключ вернулся после переподключения → сигнал по каналу', () async {
    var available = false;
    final v = ForkVerifiedDelta(toggled(() => available));
    final recovered = <String>[];
    final sub = ForkVerifiedDelta.keyRecovered.listen(recovered.add);
    expect(await v.open(channel, packet), isNull, reason: 'fail closed');
    expect(recovered, isEmpty);
    available = true;
    v.refreshKey();
    expect((await v.open(channel, packet))?['event'], 'delete');
    await pumpEventQueue();
    expect(recovered, [channel]);
    await sub.cancel();
  });

  test('ключ возвращается сам, даже если новых дельт нет', () {
    fakeAsync((async) {
      var available = false;
      final v = ForkVerifiedDelta(toggled(() => available));
      final recovered = <String>[];
      final sub = ForkVerifiedDelta.keyRecovered.listen(recovered.add);
      Map<String, dynamic>? opened = {};
      unawaited(v.open(channel, packet).then((r) => opened = r));
      async.flushMicrotasks();
      expect(opened, isNull);
      // Первая повторная попытка через 5 с — ключа всё ещё нет.
      async.elapse(const Duration(seconds: 6));
      expect(recovered, isEmpty);
      available = true;
      // Следующая — через 10 с после неё.
      async.elapse(const Duration(seconds: 10));
      expect(recovered, [channel]);
      // Канал снят с учёта: повторных сигналов нет.
      async.elapse(const Duration(minutes: 5));
      expect(recovered, [channel]);
      unawaited(sub.cancel());
    });
  });

  group('окно повторов', () {
    test('переполнение вытесняет старые, а не глушит все дельты', () {
      final w = ReplayWindow(capacity: 4);
      const now = 1000000;
      for (var i = 0; i < 4; i++) {
        expect(w.admit('n$i', now - 100 + i, now), isTrue);
      }
      // Раньше: при 8192 nonce за 10 минут отбрасывалось всё подряд.
      expect(w.admit('fresh', now, now), isTrue);
      expect(w.length, 4);
      expect(w.admit('fresh2', now + 1, now + 1), isTrue);
    });

    test('повтор вытесненного nonce не проходит', () {
      final w = ReplayWindow(capacity: 2);
      const now = 1000000;
      expect(w.admit('a', now - 50, now), isTrue);
      expect(w.admit('b', now - 40, now), isTrue);
      expect(w.admit('c', now - 30, now), isTrue); // вытеснил a
      expect(w.contains('a'), isFalse);
      expect(w.admit('a', now - 50, now), isFalse, reason: 'повтор a');
      expect(w.admit('b', now - 40, now), isFalse, reason: 'повтор b');
      expect(w.admit('d', now - 20, now), isTrue);
    });

    test('протухшие nonce уходят по времени', () {
      final w = ReplayWindow(capacity: 8192);
      expect(w.admit('a', 0, 0), isTrue);
      expect(w.admit('b', 600001, 600001), isTrue);
      expect(w.contains('a'), isFalse);
      expect(w.length, 1);
    });
  });
}
