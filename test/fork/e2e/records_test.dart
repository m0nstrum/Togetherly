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

    test('чужие коллекции и пара без ключа — как есть', () {
      final b = {'text': 'x'};
      expect(codec.encode('memories', 'm1', _gid, b), same(b));
      expect(codec.encode(_col, 'm1', 'other', b), same(b));
      expect(RecordCodec.locked().encode(_col, 'm1', _gid, b), same(b));
    });

    test('старое открытое сообщение читается (двойное чтение)', () {
      final r = {'id': 'm1', 'text': 'до E2E'};
      expect(codec.decode(_col, r), same(r));
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
      expect([for (final i in items) (i as Map)['text']], ['a', 'b']);
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
      expect(plaintextFilter('chat_messages'), contains('reactions ~ \'":\''));
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
      groupOf: (col, id, body) async => server[id]?['group_id'] as String?,
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

    test('чужие коллекции идут как есть', () async {
      final pb = PocketBase('http://pb', httpClientFactory: client);
      await pb
          .collection('memories')
          .create(body: {'id': 'mem000000000001', 'text': 'видно'});
      expect(wire.single.body, contains('видно'));
    });

    test('пара без ключа — открытым, как до E2E', () async {
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => client(withCodec: RecordCodec(c, _Keys())),
      );
      await pb
          .collection(_col)
          .create(
            body: {'id': 'msg000000000002', 'group_id': _gid, 'text': 'ok'},
          );
      expect(wire.single.body, contains('ok'));
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
  });
}
