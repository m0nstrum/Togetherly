import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/chat_hints.dart';
import 'package:love_app/models/chat_msg.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMsg _m({String text = 'привет', String? voice, String? note, int? call}) =>
    ChatMsg(
      id: 'a',
      uid: 'u',
      name: 'n',
      text: text,
      ts: 1,
      voiceUrl: voice,
      noteUrl: note,
      callMs: call,
    );

void main() {
  group('forkSendState', () {
    test('чужое всегда отправлено', () {
      expect(
        forkSendState(mine: false, pending: true, poisoned: true),
        ForkSendState.sent,
      );
    });
    test('своё: очередь, провал, готово', () {
      expect(
        forkSendState(mine: true, pending: true, poisoned: false),
        ForkSendState.queued,
      );
      expect(
        forkSendState(mine: true, pending: false, poisoned: true),
        ForkSendState.failed,
      );
      expect(
        forkSendState(mine: true, pending: false, poisoned: false),
        ForkSendState.sent,
      );
    });
  });

  group('правка и копирование', () {
    test('править можно только текст', () {
      expect(forkCanEdit(_m()), isTrue);
      expect(forkCanEdit(_m(text: '', voice: 'v.m4a')), isFalse);
      expect(forkCanEdit(_m(text: '', note: 'n.mp4')), isFalse);
      expect(forkCanEdit(_m(call: 5000)), isFalse);
    });
    test('нечитаемое не правится и не копируется', () {
      final locked = _m(text: '🔒');
      expect(forkIsLocked(locked), isTrue);
      expect(forkCanEdit(locked), isFalse);
      expect(forkCanCopy(locked), isFalse);
      expect(forkCanCopy(_m()), isTrue);
      expect(forkCanCopy(_m(text: '  ')), isFalse);
    });
  });

  test('подсказка выдаётся один раз', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ForkHints.take(ForkHints.micTap), isTrue);
    expect(await ForkHints.take(ForkHints.micTap), isFalse);
    expect(await ForkHints.take(ForkHints.gestures), isTrue);
  });
}
