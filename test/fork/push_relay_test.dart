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
}
