import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await t.tap(find.text('Retry'));
    await t.pump(const Duration(milliseconds: 300));
    expect(retried, 1);
    expect(voice.stage, VoiceStage.idle);
  });
}
