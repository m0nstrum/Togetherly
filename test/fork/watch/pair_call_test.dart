import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/pair_call.dart';
import 'package:love_app/main.dart' show LoveApp;

/// UX_AUDIT C0, T4: звонок пары один на приложение, звонят из чата.
void main() {
  testWidgets('без пары и входа «позвонить» говорит почему, а не молчит', (t) async {
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: LoveApp.rootNavigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await t.runAsync(() => ForkPairCall.instance.call(''));
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(ForkPairCall.instance.voice.value, isNull);
  });

  test('чат, главная, выход и комната подключены к общему звонку', () {
    String src(String p) => File(p).readAsStringSync();
    expect(src('lib/screens/chat_screen.dart'), contains('ForkPairCall.instance.call(_groupId)'));
    expect(src('lib/screens/home_screen.dart'), contains('ForkPairCall.instance.bind(groupId)'));
    expect(src('lib/models/user_data.dart'), contains('ForkPairCall.instance.unbind()'));
    final room = src('lib/screens/together/watch_room_screen.dart');
    expect(room, contains('ForkPairCall.instance.bind(widget.pairId, room: widget.room)'));
    expect(room, isNot(contains('_voice?.dispose()')), reason: 'разговор переживает уход из комнаты');
  });
}
