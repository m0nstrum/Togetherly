// fork: чат комнаты на ключе сессии (docs/fork/E2E.md §10.1).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/e2e/room_chat.dart';

const _gid = 'pairaaaaaaaaaaa';

class _Keys implements E2EKeyring {
  _Keys(this.k);
  final PairKey? k;
  @override
  PairKey? keyFor(String keyId) => k?.keyId == keyId ? k : null;
  @override
  PairKey? currentKey(String groupId) => groupId == _gid ? k : null;
  @override
  String? groupWith(Set<String> members) => null;
}

/// Канал комнаты: всё, что ушло, видит сервер (`wire`) и все слушатели.
class _Bus {
  final List<Map<String, dynamic>> wire = [];
  final List<void Function(Map<String, dynamic>)> _subs = [];

  RoomTransport transport() => _Transport(this);

  void publish(Map<String, dynamic> m) {
    wire.add(m);
    for (final s in List.of(_subs)) {
      scheduleMicrotask(() => s(m));
    }
  }
}

class _Transport implements RoomTransport {
  _Transport(this.bus);
  final _Bus bus;
  @override
  Future<void> send(Map<String, dynamic> msg) async => bus.publish(msg);
  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  ) async {
    bus._subs.add(onMessage);
    return () async => bus._subs.remove(onMessage);
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late E2ECrypto c;
  late PairKey pair;
  setUpAll(() async => c = await E2ECrypto.init());
  setUp(() => pair = PairKey(_gid, 1, c.symmetricKey()));

  RoomChat app(_Bus bus, String me, {PairKey? key, bool noKey = false}) =>
      RoomChat(
        room: 'ROOM1',
        groupId: _gid,
        me: me,
        name: me == 'alice' ? 'Аня' : 'Боря',
        crypto: c,
        pairKeys: _Keys(noKey ? null : (key ?? pair)),
        transport: bus.transport(),
        keyWait: const Duration(milliseconds: 30),
      );

  test(
    'ключ сессии договорён, реплики шифром, сервер текста не видит',
    () async {
      final bus = _Bus();
      final a = app(bus, 'alice');
      await a.start();
      await _settle();
      expect(a.secure, isTrue);
      final b = app(bus, 'bob');
      await b.start();
      await _settle();
      expect(b.secure, isTrue);

      expect(await b.send('привет из комнаты'), isTrue);
      await _settle();
      expect(a.messages.single.text, 'привет из комнаты');
      expect(a.messages.single.name, 'Боря');
      expect(a.messages.single.open, isFalse);
      expect(jsonEncode(bus.wire), isNot(contains('привет из комнаты')));
      expect(jsonEncode(bus.wire), isNot(contains('Боря')));
      a.dispose();
      b.dispose();
    },
  );

  test('вошедший позже получает переписку сессии', () async {
    final bus = _Bus();
    final a = app(bus, 'alice');
    await a.start();
    await _settle();
    await a.send('первое');
    final b = app(bus, 'bob');
    await b.start();
    await _settle();
    expect(b.messages.map((m) => m.text), ['первое']);
    expect(b.messages.single.mine, isFalse);
    a.dispose();
    b.dispose();
  });

  test('ключ сессии не связан с ключом пары и у каждой сессии свой', () async {
    final bus1 = _Bus(), bus2 = _Bus();
    final a1 = app(bus1, 'alice');
    final a2 = app(bus2, 'alice');
    await a1.start();
    await a2.start();
    await _settle();
    await a1.send('x');
    await a2.send('x');
    String keyOf(_Bus bus) =>
        (bus.wire.firstWhere((m) => m['t'] == 'chat')['e2e'] as String).split(
          '.',
        )[1];
    expect(keyOf(bus1), isNot(keyOf(bus2)));
    expect(keyOf(bus1), isNot(contains(_gid)));
    a1.dispose();
    a2.dispose();
  });

  test('двое завели ключ разом — сходятся на одном', () async {
    final bus = _Bus();
    final a = app(bus, 'alice');
    final b = app(bus, 'bob');
    await Future.wait([a.start(), b.start()]);
    await _settle();
    await a.send('раз');
    await b.send('два');
    await _settle();
    expect(a.messages.map((m) => m.text), containsAll(['раз', 'два']));
    expect(b.messages.map((m) => m.text), containsAll(['раз', 'два']));
    a.dispose();
    b.dispose();
  });

  test('ключ сессии под чужим ключом пары не принимается', () async {
    final bus = _Bus();
    final eve = app(bus, 'eve', key: PairKey(_gid, 1, c.symmetricKey()));
    await eve.start();
    await _settle();
    final a = app(bus, 'alice');
    await a.start();
    await _settle();
    await eve.send('подмена');
    await _settle();
    expect(a.messages, isEmpty);
    a.dispose();
    eve.dispose();
  });

  test('браузер в комнате — открытый чат с пометкой', () async {
    final bus = _Bus();
    final a = app(bus, 'alice');
    await a.start();
    await _settle();
    bus.publish({'t': 'hello', 'from': 'guest', 'web': true});
    await _settle();
    expect(a.browser, isTrue);
    expect(a.secure, isFalse);
    await a.send('видно серверу');
    expect(bus.wire.last['text'], 'видно серверу');
    bus.publish({'t': 'chat', 'from': 'guest', 'text': 'из браузера'});
    await _settle();
    expect(a.messages.last.text, 'из браузера');
    expect(a.messages.last.open, isTrue);
    a.dispose();
  });

  test('ключей пары нет — пишем открыто', () async {
    final bus = _Bus();
    final a = app(bus, 'alice', noKey: true);
    await a.start();
    await _settle();
    expect(a.openMode, isTrue);
    expect(await a.send('ок'), isTrue);
    expect(bus.wire.last['text'], 'ок');
    a.dispose();
  });
}
