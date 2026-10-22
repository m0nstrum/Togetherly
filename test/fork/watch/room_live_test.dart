import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/room_live.dart';

/// Комната как в Rave: события окна видео становятся словами.
void main() {
  var t = DateTime.fromMillisecondsSinceEpoch(1760000000000);
  ForkRoomLive make() => ForkRoomLive(partnerName: () => 'Аня', now: () => t);

  test('партнёр включил ролик и поставил паузу — строки и полоса', () {
    final live = make();
    live.handle({'t': 'source', 'by': 'partner', 'kind': 'youtube', 'label': 'YouTube', 'url': 'https://youtu.be/x'});
    live.handle({'t': 'title', 'title': 'Кино'});
    t = t.add(const Duration(seconds: 30));
    live.handle({'t': 'act', 'act': 'pause', 'playing': false, 'at': 754.0, 'by': 'partner'});
    expect(live.hasVideo, isTrue);
    expect(live.title, 'Кино');
    expect(live.playing, isFalse);
    expect(live.lines.map((l) => l.kind), ['source', 'pause']);
    expect(live.lines.first.text, contains('Аня'));
    expect(live.lines.last.text, contains('12:34'));
    expect(live.lastAct, live.lines.last.text);
  });

  test('перемотка и «играть» сразу за ней — одна строка о перемотке', () {
    final live = make();
    live.handle({'t': 'act', 'act': 'seek', 'playing': false, 'at': 60.0, 'by': 'me'});
    t = t.add(const Duration(milliseconds: 800));
    live.handle({'t': 'act', 'act': 'play', 'playing': true, 'at': 60.5, 'by': 'me'});
    expect(live.lines, hasLength(1));
    expect(live.lines.single.kind, 'seek');
    expect(live.lines.single.mine, isTrue);
    expect(live.playing, isTrue);
    t = t.add(const Duration(seconds: 10));
    live.handle({'t': 'act', 'act': 'pause', 'playing': false, 'at': 70.0, 'by': 'partner'});
    expect(live.lines, hasLength(2), reason: 'чужое действие — своя строка');
  });

  test('присутствие, отказ ссылки, просьбы страницы', () {
    final live = make();
    live.handle({'t': 'viewers', 'n': 2});
    expect(live.partnerHere, isTrue);
    live.handle({'t': 'presence', 'here': false});
    expect(live.lines.single.kind, 'gone');
    live.handle({'t': 'status', 'text': 'Играет: YouTube', 'loud': false});
    expect(live.status, 'Играет: YouTube');
    expect(live.noticeSeq, 0);
    live.handle({'t': 'status', 'text': 'Такую ссылку не открыть', 'loud': true});
    expect(live.notice, 'Такую ссылку не открыть');
    expect(live.noticeSeq, 1);
    live.handle({'t': 'pick'});
    live.handle({'t': 'fullscreen'});
    live.handle({'t': 'net', 'kind': 'offline'});
    live.handle({'t': 'manual', 'on': true});
    expect((live.pickSeq, live.fullscreenSeq, live.offline, live.manual), (1, 1, true, true));
    live.handle({'t': 'net', 'kind': 'ready'});
    expect(live.offline, isFalse);
  });

  test('часы', () {
    expect(ForkRoomLive.clock(5), '0:05');
    expect(ForkRoomLive.clock(754.9), '12:34');
    expect(ForkRoomLive.clock(3725), '1:02:05');
  });
}
