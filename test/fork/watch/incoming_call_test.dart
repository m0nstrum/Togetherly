// fork: входящий звонок в комнате и ленте (lib/services/watch_voice_service.dart).
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/incoming_call.dart';
import 'package:love_app/services/watch_channel_service.dart';
import 'package:love_app/services/watch_voice_service.dart';

class _Channel extends WatchChannel {
  _Channel() : super('room', 'b');
  final sent = <String>[];

  @override
  Future<bool> send(
    String type, {
    double at = 0,
    Map<String, dynamic>? extra,
  }) async {
    sent.add(type);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('зов при выключенном микрофоне — входящий, а не тишина', () async {
    final ch = _Channel();
    final v = WatchVoiceService(channel: ch, me: 'b');
    await v.handleMessage({'t': 'voice-hello', 'uid': 'a'});
    expect(v.ringingFrom, 'a');
    expect(v.active, isFalse);

    await v.decline();
    expect(v.ringingFrom, isEmpty);
    expect(ch.sent, ['voice-decline']);
  });

  test('звонящий передумал — входящий гаснет', () async {
    final v = WatchVoiceService(channel: _Channel(), me: 'b');
    await v.handleMessage({'t': 'voice-hello', 'uid': 'a'});
    await v.handleMessage({'t': 'voice-bye', 'uid': 'a'});
    expect(v.ringingFrom, isEmpty);
  });

  test('без ответа входящий гаснет сам', () {
    fakeAsync((fa) {
      final v = WatchVoiceService(channel: _Channel(), me: 'b');
      v.handleMessage({'t': 'voice-hello', 'uid': 'a'});
      fa.flushMicrotasks();
      expect(v.ringingFrom, 'a');
      fa.elapse(WatchVoiceService.ringFor + const Duration(seconds: 1));
      expect(v.ringingFrom, isEmpty);
    });
  });

  testWidgets('карточка: ответить зовёт экран', (tester) async {
    final v = WatchVoiceService(channel: _Channel(), me: 'b');
    var answered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForkIncomingCall(voice: v, onAnswer: () async => answered++),
        ),
      ),
    );
    expect(find.byType(FilledButton), findsNothing);
    await v.handleMessage({'t': 'voice-hello', 'uid': 'a'});
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    expect(answered, 1);
    await v.decline();
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
}
