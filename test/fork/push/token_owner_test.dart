import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/push/fcm_wake.dart';
import 'package:love_app/services/pocketbase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'conflicting token requests rotation and cannot keep FCM accepted',
    () async {
      final pb = PocketBase(
        'https://example.test',
        httpClientFactory: () => MockClient((request) async {
          return request.body.contains('foreign')
              ? http.Response('{"error":"rotate_device_token"}', 409)
              : http.Response('{"enabled":true}', 200);
        }),
      );
      PocketBaseService().debugUse(pb);
      pb.authStore.save('test-token', RecordModel({'id': 'alice'}));
      expect(await ForkPushToken.save('own'), isTrue);
      expect(ForkPushToken.accepted, isTrue);
      await expectLater(
        ForkPushToken.save('foreign'),
        throwsA(
          isA<ClientException>().having((e) => e.statusCode, 'status', 409),
        ),
      );
      expect(ForkPushToken.accepted, isFalse);
      expect(await ForkPushToken.save('rotated'), isTrue);
      pb.authStore.save('new-token', RecordModel({'id': 'bob'}));
      expect(ForkPushToken.accepted, isFalse);
      ForkPushToken.resetRegistration();
    },
  );

  test('registration completing after account switch is discarded', () async {
    final response = Completer<http.Response>();
    final pb = PocketBase(
      'https://example.test',
      httpClientFactory: () => MockClient((_) => response.future),
    );
    PocketBaseService().debugUse(pb);
    pb.authStore.save('test-token', RecordModel({'id': 'alice'}));
    final registering = ForkPushToken.save('old-token');
    pb.authStore.save('new-token', RecordModel({'id': 'bob'}));
    response.complete(http.Response('{"enabled":true}', 200));
    expect(await registering, isFalse);
    expect(ForkPushToken.accepted, isFalse);
    ForkPushToken.resetRegistration();
  });
}
