// fork: шифрование полей записей (PLAN S9) — кодек, HTTP-клиент, поиск.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/fork/e2e/chat_search.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/http_client.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/models/chat_search.dart';
import 'package:pocketbase/pocketbase.dart';

class _Keys implements E2EKeyring {
  final Map<String, PairKey> byId = {};

  void add(PairKey k) => byId[k.keyId] = k;

  @override
  PairKey? keyFor(String keyId) => byId[keyId];

  @override
  String? groupWith(Set<String> members) =>
      members.containsAll(['alice', 'bob']) && members.length == 2
      ? _gid
      : null;

  @override
  PairKey? currentKey(String groupId) {
    PairKey? best;
    for (final k in byId.values) {
      if (k.groupId == groupId && (best == null || k.epoch > best.epoch)) {
        best = k;
      }
    }
    return best;
  }
}

const _col = 'chat_messages';

http.Response _json(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
const _gid = 'pairaaaaaaaaaaa';

void main() {
  late E2ECrypto c;
  late _Keys keys;
  late RecordCodec codec;
  setUpAll(() async => c = await E2ECrypto.init());
  setUp(() {
    keys = _Keys()..add(PairKey(_gid, 1, c.symmetricKey()));
    codec = RecordCodec(c, keys);
  });

  group('кодек', () {
    test('туда и обратно, числа и пустое не трогает', () {
      final body = {
        'group_id': _gid,
        'user_name': 'Аня',
        'text': 'привет 👋',
        'reply_to_text': '',
        'ts': 1,
      };
      final enc = codec.encode(_col, 'm1', _gid, body);
      expect(enc['text'], startsWith(e2eFieldPrefix));
      expect(enc['text'], contains('$_gid:1.'));
      expect(enc['user_name'], startsWith(e2eFieldPrefix));
      expect(enc['reply_to_text'], '');
      expect(enc['ts'], 1);
      expect(enc['group_id'], _gid);
      final dec = codec.decode(_col, {'id': 'm1', ...enc});
      expect(dec['text'], 'привет 👋');
      expect(dec['user_name'], 'Аня');
      expect(dec.containsKey(e2eLockedKey), isFalse);
    });

    test('реакции — JSON-поле: шифр строкой, обратно картой', () {
      final enc = codec.encode(_col, 'm1', _gid, {
        'reactions': {'u1': '❤️'},
      });
      expect(enc['reactions'], startsWith(e2eFieldPrefix));
      expect(codec.decode(_col, {'id': 'm1', ...enc})['reactions'], {
        'u1': '❤️',
      });
      expect(
        codec.encode(_col, 'm1', _gid, {'reactions': {}})['reactions'],
        {},
      );
      final locked = RecordCodec.locked().decode(_col, {'id': 'm1', ...enc});
      expect(locked['reactions'], <String, dynamic>{});
    });

    test('чужие коллекции — как есть; без ключа открытым не пишем', () {
      final b = {'text': 'x'};
      expect(codec.encode('app_config', 'm1', _gid, b), same(b));
      expect(
        () => codec.encode(_col, 'm1', 'other', b),
        throwsA(isA<E2ENoKeyError>()),
      );
      expect(
        () => RecordCodec.locked().encode(_col, 'm1', _gid, b),
        throwsA(isA<E2ENoKeyError>()),
      );
      // Без содержимого (служебные поля, заглушка, уже шифр) — можно.
      final meta = {'ts': 1, 'deleted': true};
      expect(codec.encode(_col, 'm1', 'other', meta), same(meta));
      final ph = {'text': e2eLockedText, 'reactions': <String, dynamic>{}};
      expect(codec.encode(_col, 'm1', 'other', ph), same(ph));
      final sealed = codec.encode(_col, 'm1', _gid, {'text': 'x'});
      expect(codec.encode(_col, 'm1', 'other', sealed), same(sealed));
    });

    test('открытое содержимое по видам полей', () {
      bool has(String col, Map<String, dynamic> b) =>
          RecordCodec.hasPlainContent(col, b);
      expect(
        has('memories', {
          'data': {'type': 'photo'},
        }),
        isFalse,
      );
      expect(
        has('memories', {
          'data': {'type': 'photo', 'text': 'x'},
        }),
        isTrue,
      );
      expect(
        has('groups', {
          'member_moods': {'a': null},
        }),
        isFalse,
      );
      expect(
        has('groups', {
          'member_moods': {
            'a': {'m': 1},
          },
        }),
        isTrue,
      );
      expect(has('cycle_entries', {'day': e2eClearedDate}), isFalse);
      expect(has('cycle_entries', {'day': '2025-01-01'}), isTrue);
      expect(has('live_location', {'data': <String, dynamic>{}}), isFalse);
      expect(
        has('live_location', {
          'data': {'lat': 1},
        }),
        isTrue,
      );
    });

    test('открытое в шифрованном поле — подделка сервера, не показываем', () {
      final r = {'id': 'm1', 'text': 'подсунул сервер', 'ts': 3};
      final d = codec.decode(_col, r);
      expect(d['text'], e2eLockedText);
      expect(d['ts'], 3);
      final mem = codec.decode('memories', {
        'id': 'mem1',
        'data': {'type': 'photo', 'text': 'фальшивка', 'authorUid': 'bob'},
      });
      expect(mem['data'], {'type': 'photo', 'authorUid': 'bob'});
      final g = codec.decode('groups', {
        'id': _gid,
        'member_names': {'alice': 'Фальшивое имя'},
      });
      expect(g['member_names'], <String, dynamic>{});
      // «Салют» сервер пишет сам — его показываем.
      final salute = codec.decode('memories', {
        'id': 'mem2',
        'data': {'type': 'gift', 'giftKey': 'salute', 'title': 'Салют'},
      });
      expect((salute['data'] as Map)['title'], 'Салют');
    });

    test('шифртекст из другой записи или поля не открывается', () {
      final enc = codec.encode(_col, 'm1', _gid, {'text': 'секрет'});
      final moved = codec.decode(_col, {'id': 'm2', 'text': enc['text']});
      expect(moved['text'], e2eLockedText);
      final swapped = codec.decode(_col, {
        'id': 'm1',
        'user_name': enc['text'],
      });
      expect(swapped['user_name'], '');
      expect(swapped[e2eLockedKey], {'user_name': enc['text']});
    });

    test('нет ключа — заглушка, ключ пришёл — retry открывает', () {
      final later = PairKey(_gid, 2, c.symmetricKey());
      final sealed = codec.sealField(_col, 'm1', 'text', 'новое', later);
      final locked = codec.decode(_col, {'id': 'm1', 'text': sealed});
      expect(locked['text'], e2eLockedText);
      expect(codec.retry(_col, locked), isNull);
      keys.add(later);
      final open = codec.retry(_col, locked)!;
      expect(open['text'], 'новое');
      expect(open.containsKey(e2eLockedKey), isFalse);
    });

    test('без libsodium шифртекст прячется за заглушку', () {
      final enc = codec.encode(_col, 'm1', _gid, {'text': 'x'});
      final r = RecordCodec.locked().decode(_col, {'id': 'm1', ...enc});
      expect(r['text'], e2eLockedText);
    });

    test('ответ-страница', () {
      final enc = codec.encode(_col, 'm1', _gid, {'text': 'a'});
      final page = codec.decodeResponse(_col, {
        'page': 1,
        'items': [
          {'id': 'm1', ...enc},
          {'id': 'm2', 'text': 'b'},
        ],
      });
      final items = (page! as Map)['items'] as List;
      expect([for (final i in items) (i as Map)['text']], ['a', e2eLockedText]);
    });
  });

  group('геопозиция и цикл', () {
    test('цикл: kind и flow на месте, дата переезжает в enc', () {
      final enc = codec.encode('cycle_entries', 'c1', _gid, {
        'group_id': _gid,
        'day': '2026-10-01 00:00:00.000Z',
        'kind': 'period',
        'flow': 'heavy',
        'shared': true,
      });
      expect(enc['day'], e2eClearedDate);
      expect(enc['kind'], startsWith(e2eFieldPrefix));
      expect(enc['flow'], startsWith(e2eFieldPrefix));
      expect(enc[e2eMovedField], startsWith(e2eFieldPrefix));
      expect(enc['shared'], isTrue);
      final dec = codec.decode('cycle_entries', {'id': 'c1', ...enc});
      expect(dec['day'], '2026-10-01 00:00:00.000Z');
      expect(dec['kind'], 'period');
      expect(dec.containsKey(e2eMovedField), isFalse);

      // Переключатель видимости шлёт только `shared` — дату не трогает.
      final shared = codec.encode('cycle_entries', 'c1', _gid, {
        'shared': false,
      });
      expect(shared, {'shared': false});
    });

    test('цикл: без ключа дата за календарём, ключ пришёл — вернулась', () {
      final later = PairKey(_gid, 2, c.symmetricKey());
      final other = RecordCodec(c, _Keys()..add(later));
      final enc = other.encode('cycle_entries', 'c1', _gid, {
        'day': '2026-10-02',
        'kind': 'pms',
      });
      final locked = codec.decode('cycle_entries', {'id': 'c1', ...enc});
      expect(locked['day'], e2eClearedDate);
      expect(locked['kind'], '');
      keys.add(later);
      final open = codec.retry('cycle_entries', locked)!;
      expect(open['day'], '2026-10-02');
      expect(open['kind'], 'pms');
      expect(open.containsKey(e2eLockedKey), isFalse);
    });

    test('точка геопозиции: data — JSON, пара по каналу', () {
      expect(pairChannelMembers('pair_alice_bob'), {'alice', 'bob'});
      expect(pairChannelMembers('pair_alice'), isNull);
      expect(pairChannelMembers(_gid), isNull);
      final point = {'lat': 55.75, 'lng': 37.61, 'updatedAt': 1};
      final enc = codec.encode('live_location', 'l1', _gid, {
        'channel': 'pair_alice_bob',
        'data': point,
      });
      expect(enc['data'], startsWith(e2eFieldPrefix));
      expect(enc['channel'], 'pair_alice_bob');
      expect(
        codec.decode('live_location', {'id': 'l1', ...enc})['data'],
        point,
      );
    });

    test('живая точка в канале: AAD — канал, автор и время', () {
      final k = keys.currentKey(_gid)!;
      const place = ChannelPlace('loc:pair_alice_bob', 'point:alice', 7);
      final sealed = codec.sealChannel(place, {'lat': 1.5}, k);
      expect(codec.openChannel(place, sealed), {'lat': 1.5});
      for (final other in const [
        ChannelPlace('loc:pair_alice_bob', 'point:bob', 7),
        ChannelPlace('loc:pair_alice_bob', 'point:alice', 8),
        ChannelPlace('loc:pair_alice_eve', 'point:alice', 7),
      ]) {
        expect(codec.openChannel(other, sealed), isNull);
      }
    });

    test('фильтр открытых полей для перешифровки', () {
      expect(
        plaintextFilter('cycle_entries'),
        contains("(day != '' && day != '$e2eClearedDate')"),
      );
      expect(
        plaintextFilter('cycle_entries'),
        contains("(kind != '' && kind !~ 'e2e1.')"),
      );
      expect(plaintextFilter('chat_messages'), contains("reactions != '[]'"));
    });
  });

  group('воспоминания', () {
    final memory = {
      'id': 'mem1',
      'type': 'photo',
      'sealed': true,
      'openAt': '2027-01-01T00:00:00.000Z',
      'commentsCount': 2,
      'caption': 'море',
      'imageUrl': 'pb://media/x/y.webp',
      'latitude': 43.1,
    };

    test('data: служебные ключи открыты, содержимое — шифром в e2e', () {
      final enc = codec.encode('memories', 'mem1', _gid, {'data': memory});
      final data = enc['data'] as Map<String, dynamic>;
      expect(data['sealed'], isTrue);
      expect(data['openAt'], '2027-01-01T00:00:00.000Z');
      expect(data['commentsCount'], 2);
      expect(data[e2ePartialKey], startsWith(e2eFieldPrefix));
      for (final hidden in ['caption', 'imageUrl', 'latitude']) {
        expect(data, isNot(contains(hidden)));
      }
      final dec = codec.decode('memories', {'id': 'mem1', ...enc});
      expect(dec['data'], memory);
    });

    test('сервер поменял счётчик комментариев — шифр цел', () {
      final enc = codec.encode('memories', 'mem1', _gid, {'data': memory});
      final data = Map<String, dynamic>.of(enc['data'] as Map<String, dynamic>)
        ..['commentsCount'] = 3;
      final dec = codec.decode('memories', {'id': 'mem1', 'data': data});
      expect((dec['data'] as Map)['commentsCount'], 3);
      expect((dec['data'] as Map)['caption'], 'море');
    });

    test('запечатанная капсула приходит без e2e — как есть', () {
      final r = {
        'id': 'mem1',
        'data': {'sealed': true, 'openAt': '2027-01-01T00:00:00.000Z'},
      };
      expect(codec.decode('memories', r), same(r));
    });

    test('без ключа — только служебные ключи, потом retry', () {
      final later = PairKey(_gid, 2, c.symmetricKey());
      final enc = RecordCodec(
        c,
        _Keys()..add(later),
      ).encode('memories', 'mem1', _gid, {'data': memory});
      final locked = codec.decode('memories', {'id': 'mem1', ...enc});
      expect((locked['data'] as Map)['caption'], isNull);
      expect((locked['data'] as Map)['type'], 'photo');
      keys.add(later);
      expect(codec.retry('memories', locked)!['data'], memory);
    });

    test('комментарий — текст на месте', () {
      final enc = codec.encode('memory_comments', 'cm1', _gid, {
        'text': 'красиво',
      });
      expect(enc['text'], startsWith(e2eFieldPrefix));
      expect(
        codec.decode('memory_comments', {'id': 'cm1', ...enc})['text'],
        'красиво',
      );
    });
  });

  group('желания, виджеты, скучаю', () {
    test('желание и виджет — текст на месте, цена шифром', () {
      final w = codec.encode('wishes', 'w1', _gid, {
        'title': 'Плед',
        'url': 'https://shop/x',
        'price': 990,
        'done': false,
      });
      expect(w['title'], startsWith(e2eFieldPrefix));
      expect(w['url'], startsWith(e2eFieldPrefix));
      expect(w['price'], 0, reason: 'цена в enc');
      final wd = codec.encode('widget_data', 'wd1', _gid, {
        'status': 'на работе',
        'photo_grid_urls': ['pb://media/a/b.jpg'],
        'display_name': 'Аня',
      });
      expect(wd['status'], startsWith(e2eFieldPrefix));
      expect(wd['photo_grid_urls'], startsWith(e2eFieldPrefix));
      expect(wd['display_name'], 'Аня');
      expect(
        codec.decode('widget_data', {'id': 'wd1', ...wd})['photo_grid_urls'],
        ['pb://media/a/b.jpg'],
      );
    });

    test('«скучаю»: шифр привязан к паре и автору, а не к id записи', () {
      expect(
        e2eRecordKey('miss_you', {'group_id': _gid, 'user_uid': 'alice'}),
        '$_gid/alice',
      );
      final sealed = codec.sealField(
        'miss_you',
        '$_gid/alice',
        'text',
        'обнимаю',
        keys.currentKey(_gid)!,
      );
      final rec = {
        'id': 'любой',
        'group_id': _gid,
        'user_uid': 'alice',
        'last_vibe_text': sealed,
      };
      expect(codec.decode('miss_you', rec)['last_vibe_text'], 'обнимаю');
      // Сервер не выдаст текст одного за текст другого.
      expect(
        codec.decode('miss_you', {...rec, 'user_uid': 'bob'})['last_vibe_text'],
        '',
      );
    });

    test('маршрут miss-you: текст уходит шифром', () async {
      final wire = <String>[];
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => E2EHttpClient(
          MockClient((req) async {
            wire.add(req.body);
            return _json('{"ok":true,"count":1}');
          }),
          codec: () async => codec,
        ),
      );
      await pb.send(
        '/api/group/miss-you',
        method: 'POST',
        body: {
          'groupId': _gid,
          'uid': 'alice',
          'vibe': 'custom',
          'text': 'обнимаю',
        },
      );
      final sent = jsonDecode(wire.single) as Map<String, dynamic>;
      expect(sent['text'], startsWith(e2eFieldPrefix));
      expect(sent['vibe'], 'custom');
      final back = codec.decode('miss_you', {
        'group_id': _gid,
        'user_uid': 'alice',
        'last_vibe_text': sent['text'],
      });
      expect(back['last_vibe_text'], 'обнимаю');
    });
  });

  group('запись пары', () {
    test('словарь участников: каждое значение — свой шифр', () {
      final enc = codec.encode('groups', _gid, _gid, {
        'member_moods': {
          'alice': {'emoji': '😊', 'label': 'счастлива'},
          'bob': null,
        },
        'members': ['alice', 'bob'],
        'first_kiss_date': '2025-02-14 00:00:00.000Z',
        'start_date': '2025-01-01 00:00:00.000Z',
      });
      final moods = enc['member_moods'] as Map;
      expect(moods['alice'], startsWith(e2eFieldPrefix));
      expect(moods['bob'], isNull);
      expect(enc['members'], ['alice', 'bob']);
      expect(enc['first_kiss_date'], '');
      expect(enc['start_date'], '', reason: 'дата начала — в enc');
      final dec = codec.decode('groups', {'id': _gid, ...enc});
      expect(dec['member_moods'], {
        'alice': {'emoji': '😊', 'label': 'счастлива'},
        'bob': null,
      });
      expect(dec['first_kiss_date'], '2025-02-14 00:00:00.000Z');

      // Значение одного участника не выдать за значение другого.
      final swapped = codec.decode('groups', {
        'id': _gid,
        'member_moods': {'bob': moods['alice']},
      });
      expect(swapped['member_moods'], <String, dynamic>{});
      expect(swapped[e2eLockedKey], isNotNull);
    });

    test('маршрут patch-map: значение уходит шифром', () async {
      final wire = <String>[];
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => E2EHttpClient(
          MockClient((req) async {
            wire.add(req.body);
            return _json('{"ok":true}');
          }),
          codec: () async => codec,
        ),
      );
      await pb.send(
        '/api/group/patch-map',
        method: 'POST',
        body: {
          'groupId': _gid,
          'field': 'member_moods',
          'uid': 'alice',
          'value': {'emoji': '😊'},
        },
      );
      await pb.send(
        '/api/group/patch-map',
        method: 'POST',
        body: {
          'groupId': _gid,
          'field': 'member_names',
          'uid': 'alice',
          'value': 'Аня',
        },
      );
      final first = jsonDecode(wire[0]) as Map<String, dynamic>;
      expect(first['value'], startsWith(e2eFieldPrefix));
      final dec = codec.decode('groups', {
        'id': _gid,
        'member_moods': {'alice': first['value']},
      });
      expect(dec['member_moods'], {
        'alice': {'emoji': '😊'},
      });
      // Имена участников — тоже шифром ключа пары.
      expect(jsonDecode(wire[1])['value'], startsWith(e2eFieldPrefix));
    });
  });

  group('находки ревью', () {
    test(
      'правка записи пары без group_id шифруется (пара — сама запись)',
      () async {
        final wire = <String>[];
        final pb = PocketBase(
          'http://pb',
          httpClientFactory: () => E2EHttpClient(
            MockClient((req) async {
              wire.add(req.body);
              return _json('{"id":"$_gid"}');
            }),
            codec: () async => codec,
            context: (_, _, _) async => null,
          ),
        );
        await pb
            .collection('groups')
            .update(
              _gid,
              body: {
                'timers': [
                  {'title': 'годовщина'},
                ],
              },
            );
        expect(wire.single, isNot(contains('годовщина')));
        expect(jsonDecode(wire.single)['timers'], startsWith(e2eFieldPrefix));
      },
    );

    test('открытая дата в колонке — подделка, верим enc; null стирает', () {
      final enc = codec.encode('groups', _gid, _gid, {
        'first_kiss_date': '2020-01-01',
      });
      // Без ключа клиент не пишет: открытую дату подложил сервер.
      final dec = codec.decode('groups', {
        'id': _gid,
        ...enc,
        'first_kiss_date': '2021-05-05',
      });
      expect(dec['first_kiss_date'], '2020-01-01');
      final cleared = codec.encode('groups', _gid, _gid, {
        'first_kiss_date': null,
      });
      expect(cleared[e2eMovedField], startsWith(e2eFieldPrefix));
      final back = codec.decode('groups', {'id': _gid, ...cleared});
      expect(back['first_kiss_date'], isNull);
    });

    test('три даты пары в одном enc: правка одной не стирает другие', () {
      final first = codec.encode('groups', _gid, _gid, {
        'start_date': '2024-02-14',
        'anniversary_date': '2024-06-01',
        'first_kiss_date': '2024-02-20',
      });
      expect(first['start_date'], '');
      final ctx = codec.decode('groups', {'id': _gid, ...first});
      final edit = codec.encode('groups', _gid, _gid, {
        'anniversary_date': '2024-07-07',
      }, context: ctx);
      final back = codec.decode('groups', {'id': _gid, ...first, ...edit});
      expect(back['start_date'], '2024-02-14');
      expect(back['anniversary_date'], '2024-07-07');
      expect(back['first_kiss_date'], '2024-02-20');
    });

    test('запись с файлом в шифруемую коллекцию — поля шифром', () async {
      final sent = <String>[];
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => E2EHttpClient(
          MockClient.streaming((req, body) async {
            sent.add(utf8.decode(await body.toBytes(), allowMalformed: true));
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"id":"m1"}')),
              200,
            );
          }),
          codec: () async => codec,
          newId: () => 'moodid000000001',
        ),
      );
      await pb
          .collection('custom_moods')
          .create(
            body: {'group_id': _gid, 'label': 'вдохновение', 'emoji': '✨'},
            files: [
              http.MultipartFile.fromBytes('image', [
                1,
                2,
                3,
              ], filename: 'a.png'),
            ],
          );
      expect(sent.single, isNot(contains('вдохновение')));
      expect(sent.single, contains(e2eFieldPrefix));
    });

    test('пересохранение записи, что не открылась, не стирает шифр', () {
      final later = PairKey(_gid, 2, c.symmetricKey());
      final other = RecordCodec(c, _Keys()..add(later));
      final enc = other.encode('memories', 'mem1', _gid, {
        'data': {'type': 'photo', 'caption': 'море'},
      });
      final locked = codec.decode('memories', {'id': 'mem1', ...enc});
      final lockedMap = locked[e2eLockedKey] as Map<String, dynamic>;
      // Приложение сохраняет то, что видит: только служебные ключи.
      final resaved = codec.restoreLocked('memories', {
        'data': {'type': 'photo', 'isPinned': true},
      }, lockedMap);
      final data = resaved['data'] as Map;
      expect(data[e2ePartialKey], (enc['data'] as Map)[e2ePartialKey]);
      expect(data['isPinned'], isTrue);
      keys.add(later);
      expect(
        (codec.decode('memories', {'id': 'mem1', ...resaved})['data']
            as Map)['caption'],
        'море',
      );
    });

    test('«скучаю» без пары и автора в теле — берём их из контекста', () async {
      final wire = <String>[];
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => E2EHttpClient(
          MockClient((req) async {
            wire.add(req.body);
            return _json('{"id":"mx1"}');
          }),
          codec: () async => codec,
          context: (_, _, _) async => {'group_id': _gid, 'user_uid': 'alice'},
        ),
      );
      await pb
          .collection('miss_you')
          .update('mx1', body: {'count': 2, 'last_vibe_text': 'обнимаю'});
      final sent = jsonDecode(wire.single) as Map<String, dynamic>;
      expect(sent['last_vibe_text'], startsWith(e2eFieldPrefix));
      expect(
        codec.decode('miss_you', {
          'group_id': _gid,
          'user_uid': 'alice',
          ...sent,
        })['last_vibe_text'],
        'обнимаю',
      );
    });
  });

  group('HTTP-клиент', () {
    late List<http.Request> wire;
    late Map<String, Map<String, dynamic>> server;

    E2EHttpClient client({RecordCodec? withCodec}) => E2EHttpClient(
      MockClient((req) async {
        wire.add(req);
        final path = req.url.path;
        if (req.method == 'GET' && path.endsWith('/records')) {
          return _json(
            jsonEncode({'page': 1, 'items': server.values.toList()}),
          );
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final id = req.method == 'POST'
            ? body['id'] as String
            : path.split('/').last;
        server[id] = {...?server[id], ...body, 'id': id};
        return _json(jsonEncode(server[id]));
      }),
      codec: () async => withCodec ?? codec,
      context: (col, id, body) async => server[id],
      newId: () => 'generatedid0001',
    );

    setUp(() {
      wire = [];
      server = {};
    });

    test('в сети нет открытого текста, приложению — открытый', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      final rec = await pb
          .collection(_col)
          .create(
            body: {
              'id': 'msg000000000001',
              'group_id': _gid,
              'text': 'тайна',
              'reply_to_text': 'цитата',
              'ts': 5,
            },
          );
      expect(rec.getStringValue('text'), 'тайна');
      final sent = wire.single.body;
      expect(sent, isNot(contains('тайна')));
      expect(sent, isNot(contains('цитата')));
      expect(server['msg000000000001']!['text'], startsWith(e2eFieldPrefix));

      // Правка без group_id: пару находим по id.
      await pb
          .collection(_col)
          .update('msg000000000001', body: {'text': 'новая тайна'});
      expect(wire.last.body, isNot(contains('новая тайна')));

      final list = await pb.collection(_col).getList();
      expect(list.items.single.getStringValue('text'), 'новая тайна');
    });

    test('create без id получает id — AAD есть к чему привязать', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      await pb.collection(_col).create(body: {'group_id': _gid, 'text': 'x'});
      final sent = jsonDecode(wire.single.body) as Map<String, dynamic>;
      expect(sent['id'], 'generatedid0001');
      final back = codec.decode(_col, sent);
      expect(back['text'], 'x');
    });

    test('подарок и сундук: записка, место, звук — шифром', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      wire.clear();
      server['gift00000000001'] = {'id': 'gift00000000001', 'group_id': _gid};
      final raw = <http.Request>[];
      final c2 = E2EHttpClient(
        MockClient((req) async {
          raw.add(req);
          return _json('{"ok":true}');
        }),
        codec: () async => codec,
        context: (col, id, body) async => server[id],
      );
      final pb2 = PocketBase('http://pb', httpClientFactory: () => c2);
      await pb2.send(
        '/api/gifts/send',
        method: 'POST',
        body: {
          'giftId': 'gift00000000001',
          'groupId': _gid,
          'giftKey': 'letter',
          'note': 'люблю',
          'place': 'Питер',
          'soundMeta': '{"title":"Кино"}',
        },
      );
      await pb2.send(
        '/api/gifts/react',
        method: 'POST',
        body: {'giftId': 'gift00000000001', 'reply': 'и я'},
      );
      final sent = raw.map((r) => r.body).join();
      for (final leak in ['люблю', 'Питер', 'Кино', 'и я']) {
        expect(sent, isNot(contains(leak)), reason: leak);
      }
      final send = jsonDecode(raw.first.body) as Map<String, dynamic>;
      expect(send['giftKey'], 'letter');
      // Сервер кладёт шифр в запись как есть — приложение читает открытым.
      final rec = codec.decode('gifts', {
        'id': 'gift00000000001',
        'note': send['note'],
        'sound_meta': send['soundMeta'],
      });
      expect(rec['note'], 'люблю');
      expect(rec['sound_meta'], '{"title":"Кино"}');
      // Без ключа пары подарок с запиской не уходит.
      final c3 = E2EHttpClient(
        MockClient((req) async => _json('{}')),
        codec: () async => RecordCodec(c, _Keys()),
      );
      await expectLater(
        PocketBase('http://pb', httpClientFactory: () => c3).send(
          '/api/chest/give',
          method: 'POST',
          body: {'openId': 'o1', 'groupId': _gid, 'note': 'x'},
        ),
        throwsA(isA<ClientException>()),
      );
      expect(pb, isNotNull);
    });

    test('профиль: личным ключом, ответ входа открыт приложению', () async {
      keys.add(PairKey('alice', 0, c.symmetricKey()));
      final enc = codec.encode('users', 'alice', 'alice', {
        'display_name': 'Аня',
        'birth_date': '1999-05-01',
        'coins': 10,
      });
      expect(jsonEncode(enc), isNot(contains('Аня')));
      expect(enc['coins'], 10);
      final c4 = E2EHttpClient(
        MockClient(
          (req) async => _json(
            jsonEncode({
              'token': 't',
              'record': {'id': 'alice', ...enc},
            }),
          ),
        ),
        codec: () async => codec,
      );
      final pb4 = PocketBase('http://pb', httpClientFactory: () => c4);
      final auth = await pb4.collection('users').authRefresh();
      expect(auth.record.getStringValue('display_name'), 'Аня');
      expect(auth.record.getStringValue('birth_date'), '1999-05-01');
    });

    test('чужие коллекции идут как есть', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      await pb
          .collection('users')
          .create(body: {'id': 'mem000000000001', 'text': 'видно'});
      expect(wire.single.body, contains('видно'));
    });

    test('пара без ключа — запрос не уходит вовсе', () async {
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => client(withCodec: RecordCodec(c, _Keys())),
      );
      await expectLater(
        pb
            .collection(_col)
            .create(
              body: {'id': 'msg000000000002', 'group_id': _gid, 'text': 'ok'},
            ),
        throwsA(
          isA<ClientException>().having(
            (e) => e.originalError,
            'причина',
            isA<E2ENoKeyError>(),
          ),
        ),
      );
      expect(wire, isEmpty);
    });

    test('пару не узнать — тоже не уходит', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      await expectLater(
        pb.collection(_col).update('unknown00000001', body: {'text': 'x'}),
        throwsA(isA<ClientException>()),
      );
      expect(wire, isEmpty);
    });

    test('файл пары без ключа не уходит', () async {
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => client(withCodec: RecordCodec(c, _Keys())),
      );
      await expectLater(
        pb
            .collection('media')
            .create(
              body: {'group_id': _gid, 'kind': 'photo'},
              files: [
                http.MultipartFile.fromBytes(
                  'file',
                  utf8.encode('фото'),
                  filename: 'a.jpg',
                ),
              ],
            ),
        throwsA(isA<ClientException>()),
      );
      expect(wire, isEmpty);
    });
  });

  group('шифровать всё', () {
    test('облик сообщения и числа — шифром, в колонках заглушки', () {
      final enc = codec.encode(_col, 'm1', _gid, {
        'text': 'x',
        'voice_url': 'pb://media/abc/voice.m4a',
        'voice_peaks': '0123456789',
        'face': 'smile',
        'color': 7,
        'call_ms': 252000,
        'ts': 5,
      });
      expect(enc['voice_url'], startsWith(e2eFieldPrefix));
      expect(enc['face'], startsWith(e2eFieldPrefix));
      expect(enc['color'], 0);
      expect(enc['call_ms'], 0);
      expect(enc['ts'], 5, reason: 'по ts сортирует сервер');
      expect(jsonEncode(enc), isNot(contains('252000')));
      final back = codec.decode(_col, {'id': 'm1', ...enc});
      expect(back['voice_url'], 'pb://media/abc/voice.m4a');
      expect(back['color'], 7);
      expect(back['call_ms'], 252000);
    });

    test('автор воспоминания, реакции и наклейки — шифром', () {
      final enc = codec.encode('memories', 'mem1', _gid, {
        'author_name': 'Аня',
        'author_avatar': 'pb://media/a/ava.jpg',
        'data': {
          'type': 'photo',
          'authorName': 'Аня',
          'reactions': {'bob': '❤'},
          'stickers': {
            's1': {'id': 's1', 'mood': 'happy'},
          },
          'dailyTaskId': 'q7',
        },
      });
      final wire = jsonEncode(enc);
      for (final leak in ['Аня', 'ava.jpg', '❤', 'happy', 'q7']) {
        expect(wire, isNot(contains(leak)), reason: leak);
      }
      expect((enc['data'] as Map)['type'], 'photo');
    });

    test('наклейка: правка data шифром вместо sticker_put', () {
      final ctx = {
        'id': 'mem1',
        'group_id': _gid,
        'data': {
          'type': 'photo',
          'text': 'море',
          'stickers': {
            'old': {'id': 'old'},
          },
        },
      };
      final put = E2EHttpClient.applySticker({
        'sticker_put': {'id': 's2', 'mood': 'happy'},
      }, ctx);
      expect(put.containsKey('sticker_put'), isFalse);
      final stickers = (put['data'] as Map)['stickers'] as Map;
      expect(stickers.keys, containsAll(['old', 's2']));
      expect((put['data'] as Map)['text'], 'море');
      final del = E2EHttpClient.applySticker({'sticker_del': 'old'}, ctx);
      expect(((del['data'] as Map)['stickers'] as Map).keys, isEmpty);
      expect(
        () => E2EHttpClient.applySticker({'sticker_del': 'x'}, null),
        throwsA(isA<E2ENoKeyError>()),
      );
    });

    test('желание: цена и валюта шифром', () {
      final enc = codec.encode('wishes', 'w1', _gid, {
        'title': 'Велосипед',
        'price': 49990,
        'currency': 'RUB',
      });
      expect(enc['price'], 0);
      expect(jsonEncode(enc), isNot(contains('49990')));
      expect(jsonEncode(enc), isNot(contains('RUB')));
      final back = codec.decode('wishes', {'id': 'w1', ...enc});
      expect(back['price'], 49990);
    });
  });

  group('поиск', () {
    test('совпадения как у сервера', () {
      expect(
        ForkChatSearch.matches(ChatSearchKind.all, 'Привет, Мир', 'мир'),
        isTrue,
      );
      expect(
        ForkChatSearch.matches(ChatSearchKind.all, 'привет', 'п'),
        isFalse,
      );
      expect(
        ForkChatSearch.matches(ChatSearchKind.links, 'см https://x.ru', ''),
        isTrue,
      );
      expect(
        ForkChatSearch.matches(ChatSearchKind.links, 'нет ссылки', ''),
        isFalse,
      );
      expect(ForkChatSearch.matches(ChatSearchKind.voice, 'x', 'x'), isFalse);
    });

    test('листает историю и ищет у себя', () async {
      final all = [
        for (var i = 0; i < 450; i++)
          {
            'id': 'm${'$i'.padLeft(14, '0')}',
            'group_id': _gid,
            'ts': 1000 - i,
            'text': i % 100 == 7 ? 'нашлось $i' : 'шум $i',
          },
      ];
      var requests = 0;
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => MockClient((req) async {
          requests++;
          final f = req.url.queryParameters['filter'] ?? '';
          final m = RegExp(r'ts < (\d+)').firstMatch(f);
          final before = m == null ? null : int.parse(m.group(1)!);
          final per = int.parse(req.url.queryParameters['perPage']!);
          final items = all
              .where((r) => before == null || (r['ts']! as int) < before)
              .take(per)
              .toList();
          return _json(jsonEncode({'page': 1, 'items': items}));
        }),
      );
      final got = await ForkChatSearch.search(
        groupId: _gid,
        kind: ChatSearchKind.all,
        query: 'НАШЛОСЬ',
        limit: 3,
        pb: pb,
      );
      expect(
        [for (final r in got!) r.getStringValue('text')],
        ['нашлось 7', 'нашлось 107', 'нашлось 207'],
      );
      expect(requests, 2);
      final rest = await ForkChatSearch.search(
        groupId: _gid,
        kind: ChatSearchKind.all,
        query: 'нашлось',
        beforeTs: got.last.getIntValue('ts'),
        pb: pb,
      );
      expect(
        [for (final r in rest!) r.getStringValue('text')],
        ['нашлось 307', 'нашлось 407'],
      );
    });

    test('обрыв посреди истории помечает результат неполным', () async {
      var n = 0;
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => MockClient((req) async {
          if (n++ == 0) {
            final items = [
              for (var i = 0; i < 200; i++)
                {
                  'id': 'm${'$i'.padLeft(14, '0')}',
                  'group_id': _gid,
                  'ts': 1000 - i,
                  'text': 'шум $i',
                },
            ];
            return _json(jsonEncode({'page': 1, 'items': items}));
          }
          return http.Response('{}', 500);
        }),
      );
      final scan = ForkSearchScan();
      final got = await ForkChatSearch.search(
        groupId: _gid,
        kind: ChatSearchKind.all,
        query: 'нашлось',
        pb: pb,
        scan: scan,
      );
      expect(got, isNull);
      expect(scan.interrupted, isTrue);
      expect(scan.incomplete, isTrue);
    });
  });
}
