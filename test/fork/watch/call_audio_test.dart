import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/call_screen.dart';
import 'package:love_app/fork/watch/voice_stage.dart';
import 'package:love_app/services/watch_channel_service.dart';
import 'package:love_app/services/watch_voice_service.dart';

void main() {
  test('speaker uses the platform route and keeps state on failure', () async {
    final routes = <bool>[];
    var fail = false;
    final v = WatchVoiceService(
      channel: WatchChannel('r', 'me'),
      me: 'me',
      setSpeakerphone: (enabled) async {
        if (fail) throw StateError('audio unavailable');
        routes.add(enabled);
      },
    );
    expect(v.speakerOn, isTrue);
    expect(await v.toggleSpeaker(), isTrue);
    expect(v.speakerOn, isFalse);
    expect(routes, [false]);
    fail = true;
    expect(await v.toggleSpeaker(), isFalse);
    expect(v.speakerOn, isFalse);
    expect(v.routing, isFalse);
    fail = false;
    expect(await v.toggleSpeaker(), isTrue);
    expect(routes, [false, true]);
    v.dispose();
  });

  testWidgets('microphone and speaker can be changed while calling', (t) async {
    final routes = <bool>[];
    final v = WatchVoiceService(
      channel: WatchChannel('r', 'me'),
      me: 'me',
      setSpeakerphone: (enabled) async => routes.add(enabled),
    );
    v.debugStage(VoiceStage.calling);
    await t.pumpWidget(
      MaterialApp(
        home: ForkCallScreen(voice: v, partnerName: 'P', onRetry: () async {}),
      ),
    );
    final before = v.micOn;
    await t.tap(
      find.byIcon(before ? Icons.mic_rounded : Icons.mic_off_rounded),
    );
    await t.pump();
    expect(v.micOn, !before);
    await t.tap(find.textContaining(RegExp('Динамик|Speaker')));
    await t.pump();
    expect(routes, [false]);
    expect(v.stage, VoiceStage.calling);
    await t.pumpWidget(const SizedBox.shrink());
    v.dispose();
  });
}
