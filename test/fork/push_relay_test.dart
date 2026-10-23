import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/push/notif_tap.dart';
import 'package:love_app/fork/push_relay.dart';
import 'package:love_app/services/deep_link_service.dart';
import 'package:love_app/services/reels/reels_invite.dart';

void main() {
  test('зов в ленту: уведомление и лист в приложении', () async {
    final shown = <(String, String)>[];
    final invites = <ReelsInvite>[];
    final sub = ReelsInviteBus.instance.invites.listen(
      (e) => invites.add(e.invite),
    );

    ForkPushRelay.handle('n1', {
      'thread': 'reels',
      'title': 'Аня зовёт смотреть',
      'body': 'Shorts',
      'data': {'feed': 'shorts', 'group': 'g1', 'by': 'u1', 'name': 'Аня'},
    }, (id, t, b, {payload}) async => shown.add((t, b)));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(shown, [('Аня зовёт смотреть', 'Shorts')]);
    expect(invites.single.groupId, 'g1');
    expect(invites.single.name, 'Аня');
  });

  test('прочие виды — только уведомление', () async {
    final shown = <String>[];
    final invites = <ReelsInvite>[];
    final sub = ReelsInviteBus.instance.invites.listen(
      (e) => invites.add(e.invite),
    );
    ForkPushRelay.handle('n2', {
      'thread': 'draw',
      'title': 'Аня зовёт порисовать',
      'body': '',
    }, (id, t, b, {payload}) async => shown.add(t));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(shown, ['Аня зовёт порисовать']);
    expect(invites, isEmpty);
  });

  group('звонок (UX L6)', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    List<String> ring({required int at, bool front = false}) {
      ForkPushRelay.now = () => t0;
      ForkPushRelay.appInFront = () => front;
      final shown = <String>[];
      ForkPushRelay.handle('c1', {
        'thread': 'call',
        'title': '',
        'body': '',
        'data': {'group_id': 'g1', 'from': 'u1', 'at': '$at'},
      }, (id, t, b, {payload}) async => shown.add(b));
      return shown;
    }

    tearDown(() {
      ForkPushRelay.now = DateTime.now;
    });

    test('свежий зов в фоне — уведомление со своей подписью', () {
      final shown = ring(at: t0.millisecondsSinceEpoch - 5000);
      expect(shown, hasLength(1));
      expect(shown.single, isNotEmpty);
    });

    test('опоздавший пуш и открытое приложение — молча', () {
      expect(ring(at: t0.millisecondsSinceEpoch - 60000), isEmpty);
      expect(ring(at: 0), isEmpty);
      expect(ring(at: t0.millisecondsSinceEpoch, front: true), isEmpty);
    });
  });

  group('зов в комнату просмотра (Rave)', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    tearDown(() => ForkPushRelay.now = DateTime.now);

    List<(String, String?)> invite(int at) {
      ForkPushRelay.now = () => t0;
      final shown = <(String, String?)>[];
      ForkPushRelay.handle('w1', {
        'thread': 'watch',
        'title': '',
        'body': '',
        'data': {'group_id': 'g1', 'from': 'u1', 'at': '$at'},
      }, (id, t, b, {payload}) async => shown.add((t, payload)));
      return shown;
    }

    test('свежий зов — уведомление, тап ведёт в комнату', () {
      final shown = invite(t0.millisecondsSinceEpoch - 60000);
      expect(shown, hasLength(1));
      expect(shown.single.$1, isNotEmpty);
      expect(shown.single.$2, 'loveapp://watch');
    });

    test('старый зов — молча', () {
      expect(invite(t0.millisecondsSinceEpoch - 20 * 60000), isEmpty);
      expect(invite(0), isEmpty);
    });
  });

  test('touch invitation is fresh, localised and opens the touch route', () {
    final t0 = DateTime.utc(2026, 10, 23);
    ForkPushRelay.now = () => t0;
    final shown = <String?>[];
    void deliver(int at) => ForkPushRelay.handle(
      'touch',
      {
        'thread': 'touch',
        'data': {'group_id': 'g1', 'from': 'bob', 'at': '$at'},
      },
      (id, title, body, {payload}) async {
        shown.add(payload);
      },
    );
    try {
      deliver(t0.millisecondsSinceEpoch);
      deliver(t0.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch);
      expect(shown, ['loveapp://touch']);
    } finally {
      ForkPushRelay.now = DateTime.now;
    }
  });

  group('тап по уведомлению (UX D8)', () {
    test('«порисовать» несёт ссылку на холст', () async {
      final got = <String?>[];
      ForkPushRelay.handle('d1', {
        'thread': 'draw',
        'title': 'Аня зовёт порисовать',
        'body': '',
      }, (id, t, b, {payload}) async => got.add(payload));
      expect(got, ['loveapp://draw']);
    });

    test('ссылка уходит на главную тем же путём, что тап по виджету', () async {
      final seen = <Uri>[];
      final sub = DeepLinkService().widgetActionStream.listen(seen.add);
      ForkNotifTap.open('loveapp://draw');
      ForkNotifTap.open('https://evil.example/x');
      ForkNotifTap.open('');
      ForkNotifTap.open(null);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.map((u) => '$u'), ['loveapp://draw']);
      expect(DeepLinkService().consumePendingWidgetAction()?.host, 'draw');
    });
  });
}
