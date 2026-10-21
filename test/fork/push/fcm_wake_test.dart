// fork: будильник FCM (PLAN S12) — публикация из ящика сервера проходит по
// тем же подпискам, что и с сокета.
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/push/fcm_wake.dart';
import 'package:love_app/services/centrifugo_service.dart';
import 'package:love_app/services/pocketbase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => PocketBaseService().debugUse(PocketBase('http://127.0.0.1:9')),
  );

  test('deliver раздаёт публикацию слушателям канала', () async {
    final got = <RtEvent>[];
    final unsub = await CentrifugoService.instance.subscribeDelta(
      'user:u1',
      'fork_notify',
      got.add,
    );
    CentrifugoService.instance.deliver('user:u1', {
      'event': 'create',
      'collection': 'fork_notify',
      'record': {
        'id': 'abc',
        'collectionName': 'fork_notify',
        'thread': 'draw',
        'title': 'Т',
        'body': 'Б',
      },
    });
    // Чужой канал и чужая коллекция мимо.
    CentrifugoService.instance.deliver('user:u2', {
      'event': 'create',
      'collection': 'fork_notify',
      'record': {'id': 'x'},
    });
    CentrifugoService.instance.deliver('user:u1', {
      'event': 'create',
      'collection': 'chat_messages',
      'record': {'id': 'y'},
    });
    expect(got, hasLength(1));
    expect(got.single.action, 'create');
    expect(got.single.record?.id, 'abc');
    expect(got.single.record?.data['title'], 'Т');
    await unsub();
    await CentrifugoService.instance.reset();
  });

  test('пуш без события и без входа ничего не ломает', () async {
    expect(await ForkFcmWake.run(null), isTrue);
    expect(await ForkFcmWake.run({'event': ''}), isTrue);
    expect(ForkPushToken.accepted, isFalse);
  });
}
