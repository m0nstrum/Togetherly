import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/room_live.dart';
import 'package:love_app/fork/watch/room_shell.dart';

/// Комната как в Rave (22.10): что видно человеку вокруг окна видео.
void main() {
  Widget host(ForkRoomLive live, {VoidCallback? onPick, VoidCallback? onToggle}) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ListenableBuilder(
                listenable: live,
                builder: (_, _) => ForkRoomTopBar(
                  partnerName: 'Аня',
                  partnerHere: live.partnerHere,
                  invited: false,
                  onBack: () {},
                  onInvite: () {},
                  voice: null,
                  onCall: () {},
                  onShare: () {},
                  onCopy: () {},
                ),
              ),
              ListenableBuilder(
                listenable: live,
                builder: (_, _) => ForkNowPlaying(
                  live: live,
                  onPick: onPick ?? () {},
                  onToggle: onToggle ?? () {},
                  onTogether: () {},
                  onPauseBoth: () {},
                  onFullscreen: () {},
                ),
              ),
              Expanded(child: ForkRoomChatPanel(chat: null, live: live)),
            ],
          ),
        ),
      );

  testWidgets('пусто: «Выбрать видео», партнёра нет — «Позвать»', (tester) async {
    final live = ForkRoomLive(partnerName: () => 'Аня');
    var picked = 0;
    await tester.pumpWidget(host(live, onPick: () => picked++));
    expect(find.byKey(const ValueKey('fork-room-pick')), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget, reason: 'позвать');
    await tester.tap(find.byKey(const ValueKey('fork-room-pick')));
    expect(picked, 1);

    live.handle({'t': 'viewers', 'n': 2});
    await tester.pump();
    expect(find.byIcon(Icons.notifications_active_outlined), findsNothing, reason: 'партнёр уже здесь');
  });

  testWidgets('играет: название, кто что сделал, пауза у обоих; события — в ленте', (tester) async {
    final live = ForkRoomLive(partnerName: () => 'Аня');
    var toggled = 0;
    await tester.pumpWidget(host(live, onToggle: () => toggled++));
    live
      ..handle({'t': 'source', 'by': 'partner', 'kind': 'youtube', 'label': 'YouTube', 'url': 'u'})
      ..handle({'t': 'title', 'title': 'Кино на вечер'})
      ..handle({'t': 'act', 'act': 'play', 'playing': true, 'at': 75.0, 'by': 'partner'});
    await tester.pump();
    expect(find.text('Кино на вечер'), findsOneWidget);
    final sub = tester.widget<Text>(find.byKey(const ValueKey('fork-room-now-sub'))).data!;
    expect(sub, contains('Аня'));
    expect(sub, contains('1:15'));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget, reason: 'играет — кнопка паузы');
    await tester.tap(find.byKey(const ValueKey('fork-room-toggle')));
    expect(toggled, 1);
    // В ленте чата — обе строки: «включает» и «воспроизведение».
    expect(find.byIcon(Icons.movie_creation_outlined), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('без чата — поле закрыто и сказано почему', (tester) async {
    final live = ForkRoomLive(partnerName: () => 'Аня');
    await tester.pumpWidget(host(live));
    final field = tester.widget<TextField>(find.byKey(const ValueKey('fork-room-input')));
    expect(field.enabled, isFalse);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('узкий телефон (320) — ничего не вылезает', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = ForkRoomLive(partnerName: () => 'Анастасия-Длинное-Имя');
    await tester.pumpWidget(host(live));
    live
      ..handle({'t': 'source', 'by': 'me', 'kind': 'youtube', 'label': 'YouTube', 'url': 'u'})
      ..handle({'t': 'title', 'title': 'Очень длинное название ролика, которое не влезет в одну строку'})
      ..handle({'t': 'manual', 'on': true});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('экран комнаты собран вокруг окна видео', () {
    final src = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    // Страница — только окно видео, события идут мостом forkRoom.
    expect(src, contains("window.__forkShell=true"));
    expect(src, contains("handlerName: 'forkRoom'"));
    expect(src, contains('_shell ? _shellBody(context)'));
    // Браузер первым ребёнком: поворот не перезагружает страницу.
    final body = src.substring(src.indexOf('Widget _shellBody('));
    expect(body.indexOf('_webView(context)'), lessThan(body.indexOf('ForkRoomTopBar(')));
    // Чат один на обе раскладки: его держит экран.
    expect(src, contains('forkStartRoomChat(widget.room, widget.pairId)'));
    expect(src, contains('ForkRoomChatOverlay(room: widget.room, groupId: widget.pairId, chat: _chat)'));
  });
}
