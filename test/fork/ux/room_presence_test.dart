import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UX_AUDIT L8, L11, L15: комната и лента говорят, что партнёр пришёл и
/// ушёл, держат плашку «нет связи», а «▶» верит плееру.
void main() {
  final room = File(
    'pocketbase/pb_public/watch/room/room.js',
  ).readAsStringSync();
  final reels = File(
    'pocketbase/pb_public/watch/reels/reels.js',
  ).readAsStringSync();
  final i18n = File('pocketbase/pb_public/watch/i18n.js').readAsStringSync();

  test('уход партнёра виден в обоих', () {
    expect(room, contains("I18N.t('room.partnerLeft')"));
    expect(i18n.split("'room.partnerLeft'").length - 1, 2, reason: 'ru и en');
    expect(reels, contains('T.left'));
    expect(
      room,
      contains('joinedAt: -Infinity'),
      reason: 'приход видно и в первые 30 с',
    );
  });

  test('нет связи — плашка, пока не вернётся', () {
    expect(room, contains('function netBanner'));
    expect(reels, contains('function netBanner'));
    expect(reels, contains("netBanner(kind === 'lost' || kind === 'offline')"));
  });

  test('«▶» сверяется с плеером', () {
    expect(reels, contains('S.pausedAt'));
    expect(
      reels,
      contains("el.root.classList.remove('is-paused');\n        }"),
    );
  });

  test('видео говорит, что не так (V2, V7, V8, V6)', () {
    expect(room, contains('onError: (e) =>'));
    expect(room, contains("'room.ytNoEmbed'"));
    expect(room, contains("I18N.t('room.badFile')"));
    expect(room, contains("addEventListener('loadedmetadata', announce"));
    expect(room, contains('window.forkExitCinema'));
    expect(room, contains('function cinemaViewers'));
    for (final k in [
      'room.opening',
      'room.ytNoApi',
      'room.ytNoEmbed',
      'room.ytGone',
      'room.ytFailed',
      'room.badFile',
    ]) {
      expect(i18n.split("'$k'").length - 1, 2, reason: '$k: ru и en');
    }
    final screen = File(
      'lib/screens/together/watch_room_screen.dart',
    ).readAsStringSync();
    expect(
      screen,
      contains('window.forkExitCinema ? window.forkExitCinema() : false'),
    );
  });

  test('лента не висит молча (L9, L10, L13)', () {
    expect(reels, contains('function armStall'));
    expect(reels, contains('say(T.nothingNew)'));
    expect(reels, contains('T.takeHint'));
  });
}
