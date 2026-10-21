// fork: обмен ключами пары против настоящего сервера (PLAN S8, критерий).
//
// Запускается из server/scripts/smoke.sh после того, как он завёл пару:
//   SMOKE_AFTER='flutter test test/fork/e2e/live_test.dart --tags fork-live' \
//     server/scripts/smoke.sh
@Tags(['fork-live'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'package:love_app/fork/e2e/http_client.dart';
import 'package:love_app/fork/e2e/pb_backend.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/services/offline/pb_id.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  final env = Platform.environment;
  final base = env['SMOKE_BASE_URL'];

  test(
    'две установки получают общий ключ пары через сервер; сверка эмодзи; бэкап',
    () async {
      final c = await E2ECrypto.init();
      final url = base!;
      E2EService install(String tok, String uid) {
        final pb = PocketBase(url)..authStore.save(tok, null);
        return E2EService(
          crypto: c,
          store: E2EKeyStore(c, MemoryVault()),
          backend: PbE2EBackend(pb),
          uid: uid,
        );
      }

      final pair = env['SMOKE_PAIR']!;
      final a = install(env['SMOKE_ATOK']!, env['SMOKE_AID']!);
      final b = install(env['SMOKE_BTOK']!, env['SMOKE_BID']!);
      await a.start();
      await b.start();
      for (var i = 0; i < 2; i++) {
        await a.syncGroup(pair);
        await b.syncGroup(pair);
      }
      expect(a.currentKey(pair), isNotNull);
      expect(
        a.currentKey(pair)!.key.extractBytes(),
        b.currentKey(pair)!.key.extractBytes(),
      );
      expect(a.status.value[pair], PairE2EStatus.unverified);

      // Чат (S9): сервер хранит шифртекст, партнёр читает текст. Длинное
      // кириллическое сообщение влезает в поле после шифрования.
      PocketBase chat(String tok, E2EService s) => PocketBase(
        url,
        httpClientFactory: () => E2EHttpClient(
          http.Client(),
          codec: () async => RecordCodec(c, s),
          groupOf: (_, _, body) async {
            final m = pairChannelMembers(body['channel']);
            return m == null ? pair : s.groupWith(m);
          },
          newId: newPbId,
        ),
      )..authStore.save(tok, null);
      final long = 'Ж' * 5000;
      final id = newPbId();
      final sent = await chat(env['SMOKE_ATOK']!, a)
          .collection('chat_messages')
          .create(
            body: {
              'id': id,
              'group_id': pair,
              'user_uid': a.uid,
              'user_name': 'Алиса',
              'text': long,
              'ts': DateTime.now().millisecondsSinceEpoch,
            },
          );
      expect(sent.getStringValue('text'), long);
      final raw =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('chat_messages')
              .getOne(id);
      expect(raw.getStringValue('text'), startsWith(e2eFieldPrefix));
      expect(raw.getStringValue('user_name'), isNot(contains('Алиса')));
      final bobChat = chat(env['SMOKE_BTOK']!, b);
      expect(
        (await bobChat.collection('chat_messages').getOne(id)).getStringValue(
          'text',
        ),
        long,
      );
      await chat(
        env['SMOKE_ATOK']!,
        a,
      ).collection('chat_messages').update(id, body: {'text': 'правка'});
      expect(
        (await bobChat.collection('chat_messages').getOne(id)).getStringValue(
          'text',
        ),
        'правка',
      );

      // Цикл и геопозиция (S9.2): дата отметки и координаты — только шифром.
      final cycleId = newPbId();
      await chat(env['SMOKE_ATOK']!, a)
          .collection('cycle_entries')
          .create(
            body: {
              'id': cycleId,
              'group_id': pair,
              'user_uid': a.uid,
              'day': '2026-10-01 00:00:00.000Z',
              'kind': 'period',
              'flow': 'heavy',
              'shared': true,
            },
          );
      final rawCycle =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('cycle_entries')
              .getOne(cycleId);
      expect(rawCycle.getStringValue('day'), e2eClearedDate);
      expect(rawCycle.getStringValue('kind'), startsWith(e2eFieldPrefix));
      expect(rawCycle.getStringValue('enc'), startsWith(e2eFieldPrefix));
      final bobCycle = await bobChat
          .collection('cycle_entries')
          .getOne(cycleId);
      expect(bobCycle.getStringValue('day'), '2026-10-01 00:00:00.000Z');
      expect(bobCycle.getStringValue('kind'), 'period');

      final ids = [a.uid, b.uid]..sort();
      final channel = 'pair_${ids[0]}_${ids[1]}';
      final loc = await chat(env['SMOKE_ATOK']!, a)
          .collection('live_location')
          .create(
            body: {
              'channel': channel,
              'user_uid': a.uid,
              'data': {'lat': 55.75, 'lng': 37.61},
            },
          );
      final rawLoc =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('live_location')
              .getOne(loc.id);
      expect(rawLoc.data['data'], startsWith(e2eFieldPrefix));
      final bobLoc = await bobChat.collection('live_location').getOne(loc.id);
      expect(bobLoc.data['data'], {'lat': 55.75, 'lng': 37.61});

      await a.sasStart(pair, b.uid);
      await b.syncGroup(pair);
      await b.sasAccept();
      await a.syncGroup(pair);
      await b.syncGroup(pair);
      final ca = a.sas.value, cb = b.sas.value;
      expect(ca, isA<SasShowCode>());
      expect((ca as SasShowCode).code, (cb as SasShowCode).code);
      await a.sasConfirm(match: true);
      await b.sasConfirm(match: true);
      expect(a.status.value[pair], PairE2EStatus.verified);
      expect(b.status.value[pair], PairE2EStatus.verified);

      // Бэкап ключей через сервер и восстановление на «новом телефоне».
      await a.enableBackup(BackupMethod.password, 'Ябл0ко-Кит-Велик');
      final a2 = install(env['SMOKE_ATOK']!, env['SMOKE_AID']!);
      await a2.start();
      expect(a2.needsRestore.value, isTrue);
      await a2.restore('Ябл0ко-Кит-Велик');
      expect(
        a2.currentKey(pair)!.key.extractBytes(),
        b.currentKey(pair)!.key.extractBytes(),
      );
    },
    skip: base == null
        ? 'нужен сервер: запускайте через server/scripts/smoke.sh'
        : false,
  );
}
