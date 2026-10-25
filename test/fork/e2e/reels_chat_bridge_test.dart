// fork: чат ленты вдвоём на ключе сессии (lib/fork/e2e/reels_chat_bridge.dart).
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/e2e/reels_chat_bridge.dart';
import 'package:love_app/fork/e2e/room_chat.dart';
import 'package:love_app/fork/watch/pair_call.dart';

const _gid = 'pairaaaaaaaaaaa';

class _Keys implements E2EKeyring {
  _Keys(this.k);
  final PairKey k;
  @override
  PairKey? keyFor(String keyId) => k.keyId == keyId ? k : null;
  @override
  PairKey? currentKey(String groupId) => groupId == _gid ? k : null;
  @override
  String? groupWith(Set<String> members) => null;
}

class _Bus implements RoomTransport {
  final wire = <Map<String, dynamic>>[];
  final _subs = <void Function(Map<String, dynamic>)>[];
  @override
  Future<void> send(Map<String, dynamic> msg) async {
    wire.add(msg);
    for (final s in List.of(_subs)) {
      scheduleMicrotask(() => s(msg));
    }
  }

  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  ) async {
    _subs.add(onMessage);
    return () async => _subs.remove(onMessage);
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  var aliceName = 'Аня';
  tearDown(() {
    aliceName = 'Аня';
    ForkPairCall.instance.partnerName = '';
  });

  test(
    'B3: реплика без имени подписана именем партнёра, а не «Гость»',
    () async {
      aliceName = '';
      ForkPairCall.instance.partnerName = 'Аня';
      final c = await E2ECrypto.init();
      final pair = PairKey(_gid, 1, c.symmetricKey());
      final bus = _Bus();
      final pageB = <Map<String, dynamic>>[];
      ForkReelsChatBridge bridge(String me, List<Map<String, dynamic>> page) =>
          ForkReelsChatBridge(
            room: 'ROOM1',
            groupId: _gid,
            chat: RoomChat(
              room: 'ROOM1',
              groupId: _gid,
              me: me,
              name: me == 'alice' ? aliceName : 'Боря',
              crypto: c,
              pairKeys: _Keys(pair),
              transport: bus,
              keyWait: const Duration(milliseconds: 30),
            ),
            eval: (js) async {
              final m = RegExp(r'forkChatIn\((.*)\)$').firstMatch(js);
              if (m != null) {
                page.add(jsonDecode(m.group(1)!) as Map<String, dynamic>);
              }
            },
          );
      final a = bridge('alice', <Map<String, dynamic>>[])..pageReady();
      final b = bridge('bob', pageB)..pageReady();
      await a.start();
      await b.start();
      await _settle();
      await a.send('привет');
      await _settle();
      expect(pageB.where((m) => m['sys'] != true).single['name'], 'Аня');
      a.dispose();
      b.dispose();
    },
  );

  test('реплики ленты: на странице у обоих, на сервере шифр', () async {
    final c = await E2ECrypto.init();
    final pair = PairKey(_gid, 1, c.symmetricKey());
    final bus = _Bus();
    RoomChat chat(String me) => RoomChat(
      room: 'ROOM1',
      groupId: _gid,
      me: me,
      name: me == 'alice' ? aliceName : 'Боря',
      crypto: c,
      pairKeys: _Keys(pair),
      transport: bus,
      keyWait: const Duration(milliseconds: 30),
    );
    final pageA = <Map<String, dynamic>>[];
    final pageB = <Map<String, dynamic>>[];
    ForkReelsChatBridge bridge(String me, List<Map<String, dynamic>> page) =>
        ForkReelsChatBridge(
          room: 'ROOM1',
          groupId: _gid,
          chat: chat(me),
          eval: (js) async {
            final m = RegExp(r'forkChatIn\((.*)\)$').firstMatch(js);
            if (m != null)
              page.add(jsonDecode(m.group(1)!) as Map<String, dynamic>);
          },
        );
    final a = bridge('alice', pageA)..pageReady();
    final b = bridge('bob', pageB)..pageReady();
    await a.start();
    await b.start();
    await _settle();

    await a.send('смешной котик');
    await _settle();

    expect(pageA.where((m) => m['mine'] == true).map((m) => m['text']), [
      'смешной котик',
    ]);
    expect(pageB.where((m) => m['sys'] != true).single, {
      'name': 'Аня',
      'text': 'смешной котик',
      'mine': false,
    });
    expect(
      pageB.any((m) => m['sys'] == true && '${m['text']}'.contains('🔒')),
      isTrue,
    );
    expect(
      jsonEncode(bus.wire),
      isNot(contains('котик')),
      reason: 'сервер видит только шифр',
    );
    a.dispose();
    b.dispose();
  });
}
