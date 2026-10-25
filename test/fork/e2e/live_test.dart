// fork: обмен ключами пары против настоящего сервера (PLAN S8, критерий).
//
// Запускается из server/scripts/smoke.sh после того, как он завёл пару:
//   SMOKE_AFTER='flutter test test/fork/e2e/live_test.dart --tags fork-live' \
//     server/scripts/smoke.sh
@Tags(['fork-live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/device_link.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'package:love_app/fork/e2e/media_cipher.dart';
import 'package:love_app/fork/e2e/media_proxy.dart';
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
          context: (_, _, body) async {
            final m = pairChannelMembers(body['channel']);
            return {'group_id': m == null ? pair : s.groupWith(m)};
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

      // Воспоминание (S9.3): служебные ключи открыты, содержимое — шифром.
      final mem = await chat(env['SMOKE_ATOK']!, a)
          .collection('memories')
          .create(
            body: {
              'group_id': pair,
              'type': 'photo',
              'author_uid': a.uid,
              'created_at': '2026-10-01 00:00:00.000Z',
              'data': {
                'type': 'photo',
                'commentsCount': 0,
                'caption': 'море',
                'latitude': 43.1,
              },
            },
          );
      final rawMem =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('memories')
              .getOne(mem.id);
      expect(rawMem.data['data']['type'], 'photo');
      expect(rawMem.data['data'], isNot(contains('caption')));
      expect(rawMem.data['data']['e2e'], startsWith(e2eFieldPrefix));
      final bobMem = await bobChat.collection('memories').getOne(mem.id);
      expect(bobMem.data['data']['caption'], 'море');

      // Файл (S9.3): на сервере шифр, партнёр получает открытые байты через
      // локальный прокси, перемотка (Range) работает.
      final photo = Uint8List.fromList(
        List.generate(150000, (i) => (i * 31 + 7) & 0xff),
      );
      final media = await chat(env['SMOKE_ATOK']!, a)
          .collection('media')
          .create(
            body: {'uid': a.uid, 'group_id': pair, 'kind': 'memory'},
            files: [
              http.MultipartFile.fromBytes('file', photo, filename: 'p.jpg'),
            ],
          );
      final bobPb = PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null);
      final fileUrl =
          '$url/api/files/media/${media.id}/${media.getStringValue('file')}'
          '?token=${await bobPb.files.getToken()}';
      final rawFile = await http.readBytes(Uri.parse(fileUrl));
      expect(rawFile.sublist(0, 8), mediaMagic);
      expect(rawFile.length, greaterThan(photo.length));
      final proxy = MediaProxy(codec: () async => RecordCodec(c, b));
      final viaProxy = await proxy.wrap(fileUrl);
      expect(await http.readBytes(Uri.parse(viaProxy)), photo);
      final part = await http.get(
        Uri.parse(viaProxy),
        headers: {'range': 'bytes=70000-70009'},
      );
      expect(part.statusCode, 206);
      expect(part.bodyBytes, photo.sublist(70000, 70010));
      await proxy.close();

      // Желание и «скучаю» через маршрут сервера (S9.4).
      final wish = await chat(env['SMOKE_ATOK']!, a)
          .collection('wishes')
          .create(
            body: {
              'group_id': pair,
              'author_uid': a.uid,
              'title': 'Плед',
              'price': 990,
            },
          );
      final rawWish =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('wishes')
              .getOne(wish.id);
      expect(rawWish.getStringValue('title'), startsWith(e2eFieldPrefix));
      expect(
        (await bobChat.collection('wishes').getOne(wish.id)).getStringValue(
          'title',
        ),
        'Плед',
      );
      // Партнёр отмечает чужое желание: дата отметки уходит шифром в `enc`,
      // «я тоже хочу» — в `also`; сервер пускает не-автора в эти поля, а
      // цена автора в `enc` не теряется (docs/WISHLIST.md).
      // Контекст правки — расшифрованная запись, как у приложения (кэш или
      // сервер): из неё кодек добирает в `enc` чужие поля (цену).
      final bobFull = PocketBase(
        url,
        httpClientFactory: () => E2EHttpClient(
          http.Client(),
          codec: () async => RecordCodec(c, b),
          context: (col, id, _) async =>
              (await bobChat.collection(col).getOne(id)).toJson(),
          newId: newPbId,
        ),
      )..authStore.save(env['SMOKE_BTOK']!, null);
      await bobFull.collection('wishes').update(
        wish.id,
        body: {
          'done': true,
          'done_at': DateTime.utc(2026, 10, 25).toIso8601String(),
          'done_by': b.uid,
          'also': b.uid,
        },
      );
      final marked = await chat(env['SMOKE_ATOK']!, a)
          .collection('wishes')
          .getOne(wish.id);
      expect(marked.getBoolValue('done'), isTrue);
      expect(marked.getStringValue('also'), b.uid);
      expect(marked.getIntValue('price'), 990);
      expect(marked.getStringValue('done_at'), startsWith('2026-10-25'));
      await chat(env['SMOKE_ATOK']!, a).send(
        '/api/group/miss-you',
        method: 'POST',
        body: {
          'groupId': pair,
          'uid': a.uid,
          'vibe': 'custom',
          'text': 'обнимаю',
          'weekday': 1,
        },
      );
      final miss = await bobChat
          .collection('miss_you')
          .getFirstListItem('group_id = "$pair" && user_uid = "${a.uid}"');
      expect(miss.getStringValue('last_vibe_text'), 'обнимаю');
      final rawMiss =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('miss_you')
              .getOne(miss.id);
      expect(
        rawMiss.getStringValue('last_vibe_text'),
        startsWith(e2eFieldPrefix),
      );

      // Запись пары: настроение участника через маршрут сервера.
      await chat(env['SMOKE_ATOK']!, a).send(
        '/api/group/patch-map',
        method: 'POST',
        body: {
          'groupId': pair,
          'field': 'member_moods',
          'uid': a.uid,
          'value': {'emoji': '😊'},
        },
      );
      final rawGroup =
          await (PocketBase(url)..authStore.save(env['SMOKE_BTOK']!, null))
              .collection('groups')
              .getOne(pair);
      expect(rawGroup.data['member_moods'][a.uid], startsWith(e2eFieldPrefix));
      final bobGroup = await bobChat.collection('groups').getOne(pair);
      expect(bobGroup.data['member_moods'][a.uid], {'emoji': '😊'});

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

      // Главная проверка S9: в базе и файлах сервера нет открытого текста
      // из всего, что выше ушло шифром.
      final dataDir = env['SMOKE_DATA_DIR'] ?? '';
      if (dataDir.isNotEmpty) {
        final markers = <String, List<int>>{
          for (final m in [
            'Алиса',
            'правка',
            'море',
            'Плед',
            'обнимаю',
            'Ж' * 10,
          ])
            m: utf8.encode(m),
          'фото': photo.sublist(1000, 1032),
        };
        final leaks = <String>[];
        for (final f in Directory(dataDir).listSync(recursive: true)) {
          if (f is! File) continue;
          final bytes = f.readAsBytesSync();
          for (final e in markers.entries) {
            if (_contains(bytes, e.value)) leaks.add('${e.key} в ${f.path}');
          }
        }
        expect(leaks, isEmpty);
      }

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

      // T3: третий телефон привязывается по QR с первого через e2e_links.
      final a3 = install(env['SMOKE_ATOK']!, env['SMOKE_AID']!);
      await a3.start();
      expect(a3.needsRestore.value, isTrue);
      final qr = await a3.linkStart();
      expect(await a3.linkPoll(), isFalse);
      // Чужой аккаунт запись привязки не видит.
      await expectLater(
        b.linkApprove(LinkQr(uid: b.uid, linkId: qr.linkId, secret: qr.secret)),
        throwsA(isA<E2ELinkExpired>()),
      );
      await a.linkApprove(qr);
      expect(await a3.linkPoll(), isTrue);
      expect(
        a3.currentKey(pair)!.key.extractBytes(),
        b.currentKey(pair)!.key.extractBytes(),
      );
      await b.syncGroup(pair);
      expect(b.status.value[pair], PairE2EStatus.verified,
          reason: 'новое устройство того же аккаунта — без смены ключа');
    },
    skip: base == null
        ? 'нужен сервер: запускайте через server/scripts/smoke.sh'
        : false,
  );
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
