import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/push_relay.dart';
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
    }, (id, t, b) async => shown.add((t, b)));
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
    }, (id, t, b) async => shown.add(t));
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
      }, (id, t, b) async => shown.add(b));
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
}
