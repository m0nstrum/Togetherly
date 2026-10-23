// fork: панель чата комнаты (docs/fork/E2E.md §10.1).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/e2e/room_chat.dart';
import 'package:love_app/fork/e2e/room_chat_ui.dart';

class _Keys implements E2EKeyring {
  _Keys(this.k);
  final PairKey? k;
  @override
  PairKey? keyFor(String keyId) => k?.keyId == keyId ? k : null;
  @override
  PairKey? currentKey(String groupId) => k;
  @override
  String? groupWith(Set<String> members) => null;
}

class _Loop implements RoomTransport {
  final sent = <Map<String, dynamic>>[];
  bool failChat = false;
  void Function(Map<String, dynamic>)? _on;
  void deliver(Map<String, dynamic> m) => _on?.call(m);
  @override
  Future<void> send(Map<String, dynamic> msg) async {
    if (failChat && msg['t'] == 'chat') throw StateError('offline');
    sent.add(msg);
  }

  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  ) async {
    _on = onMessage;
    return () async => _on = null;
  }
}

void main() {
  late E2ECrypto c;
  setUpAll(() async => c = await E2ECrypto.init());

  testWidgets('no pair key disables composing and sending', (t) async {
    final chat = RoomChat(
      room: 'R',
      groupId: 'g',
      me: 'a',
      name: 'A',
      crypto: c,
      pairKeys: _Keys(null),
      transport: _Loop(),
    );
    await chat.start();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ForkRoomChatOverlay(room: 'R', groupId: 'g', chat: chat),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.byIcon(Icons.chat_bubble_outline));
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      t
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );
    expect(find.textContaining(RegExp('Ключи пары|Pair keys')), findsWidgets);
    await t.pumpWidget(const SizedBox.shrink());
    chat.dispose();
  });

  testWidgets(
    'publication failure shows retry and preserves the draft in a bubble',
    (t) async {
      final loop = _Loop();
      final chat = RoomChat(
        room: 'R',
        groupId: 'g',
        me: 'a',
        name: 'A',
        crypto: c,
        pairKeys: _Keys(PairKey('g', 1, c.symmetricKey())),
        transport: loop,
        keyWait: Duration.zero,
      );
      await t.runAsync(() async {
        await chat.start();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                ForkRoomChatOverlay(room: 'R', groupId: 'g', chat: chat),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byIcon(Icons.chat_bubble_outline));
      await t.pump();
      loop.failChat = true;
      await t.enterText(find.byType(TextField), 'keep this');
      await t.tap(find.byIcon(Icons.send));
      await t.pumpAndSettle();
      expect(find.text('keep this'), findsOneWidget);
      final retry = find.textContaining(RegExp('Не отправлено|Not sent'));
      expect(retry, findsOneWidget);
      loop.failChat = false;
      await t.tap(retry);
      await t.pumpAndSettle();
      expect(retry, findsNothing);
      expect(chat.messages, hasLength(1));
      await t.pumpWidget(const SizedBox.shrink());
      chat.dispose();
    },
  );

  testWidgets('кнопка, непрочитанное, панель и честная строка', (t) async {
    final loop = _Loop();
    final chat = RoomChat(
      room: 'R',
      groupId: 'g',
      me: 'alice',
      name: 'Аня',
      crypto: c,
      pairKeys: _Keys(PairKey('g', 1, c.symmetricKey())),
      transport: loop,
      keyWait: Duration.zero,
    );
    await t.runAsync(() async {
      await chat.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ForkRoomChatOverlay(room: 'R', groupId: 'g', chat: chat),
            ],
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);

    // Открытая реплика: браузер в комнате (или подделка сервера) — не
    // показываем, пока человек не разрешит.
    loop.deliver({'t': 'chat', 'from': 'guest', 'text': 'привет'});
    await t.pump();
    expect(find.text('1'), findsNothing);
    await t.tap(find.byIcon(Icons.chat_bubble_outline));
    await t.pump();
    expect(find.text('привет'), findsNothing);
    expect(find.textContaining(RegExp('браузер|browser')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await t.tap(find.byType(TextButton));
    await t.pump();
    loop.deliver({'t': 'chat', 'from': 'guest', 'text': 'привет'});
    await t.pump();
    expect(find.text('привет'), findsOneWidget);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    chat.dispose();
  });
}
