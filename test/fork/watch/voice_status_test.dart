import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/call_screen.dart';
import 'package:love_app/fork/watch/voice_stage.dart';
import 'package:love_app/fork/watch/voice_status.dart';
import 'package:love_app/services/watch_channel_service.dart';
import 'package:love_app/services/watch_voice_service.dart';

/// UX_AUDIT L2–L7, L12: у каждой стадии звонка свои слова и выход.
void main() {
  test('у каждой стадии и причины — свой текст', () {
    final seen = <String>{};
    for (final s in VoiceStage.values.where((s) => s != VoiceStage.idle && s != VoiceStage.failed)) {
      seen.add(voiceStageText(s, null, name: 'Аня'));
    }
    for (final p in VoiceProblem.values) {
      seen.add(voiceStageText(VoiceStage.failed, p, name: 'Аня'));
    }
    expect(seen.length, VoiceStage.values.length - 2 + VoiceProblem.values.length);
    expect(voiceStageText(VoiceStage.idle, null), isEmpty);
    expect(
      voiceStageText(VoiceStage.live, null, talked: const Duration(seconds: 75)),
      contains('1:15'),
    );
  });

  testWidgets('плашка: зовём → отменить, не вышло → повторить', (t) async {
    final voice = WatchVoiceService(channel: WatchChannel('r', 'me'), me: 'me');
    var retried = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ForkVoiceStatus(voice: voice, onRetry: () async => retried++),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);

    voice.debugStage(VoiceStage.calling);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Calling'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    voice.debugStage(VoiceStage.failed, VoiceProblem.noRoute);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('TURN'), findsOneWidget);
    await t.tap(find.text('Call again'));
    await t.pump(const Duration(milliseconds: 300));
    expect(retried, 1);
    expect(voice.stage, VoiceStage.idle);
  });

  testWidgets('«не ответил» закрывается крестиком, без нового звонка',
      (t) async {
    final voice = WatchVoiceService(channel: WatchChannel('r', 'me'), me: 'me');
    var retried = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ForkVoiceStatus(voice: voice, onRetry: () async => retried++),
        ]),
      ),
    ));
    voice.debugStage(VoiceStage.failed, VoiceProblem.noAnswer);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump(const Duration(milliseconds: 300));
    expect(voice.stage, VoiceStage.idle);
    expect(retried, 0);
  });

  testWidgets('касание по плашке — звонок на весь экран, «свернуть» — назад',
      (t) async {
    final voice = WatchVoiceService(channel: WatchChannel('r', 'me'), me: 'me');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ForkVoiceStatus(
              voice: voice, partnerName: 'Аня', onRetry: () async {}),
        ]),
      ),
    ));
    voice.debugStage(VoiceStage.calling);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.textContaining('Calling'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ForkCallScreen), findsOneWidget);
    expect(ForkCallScreen.visible.value, isTrue);
    expect(find.text('Аня'), findsOneWidget);

    await t.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ForkCallScreen), findsNothing);
    expect(ForkCallScreen.visible.value, isFalse);
    expect(find.textContaining('Calling'), findsOneWidget,
        reason: 'свернули — плашка снова видна, звонок идёт');

    // Звонок кончился, пока экран открыт, — экран закрывается сам.
    await t.tap(find.textContaining('Calling'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    voice.debugStage(VoiceStage.idle);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ForkCallScreen), findsNothing);
  });
}
