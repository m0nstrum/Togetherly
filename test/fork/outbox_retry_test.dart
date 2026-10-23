import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:love_app/fork/outbox_attempt.dart';
import 'package:love_app/services/offline/local_store.dart';
import 'package:love_app/services/offline/outbox_service.dart';

void main() {
  final box = OutboxService.instance;
  final pending = intMapStoreFactory.store('outbox');
  final poison = intMapStoreFactory.store('outbox_poison');
  late Database db;
  setUp(() async {
    await LocalStore.instance.initWith(
      databaseFactoryMemory,
      'retry-outbox.db',
    );
    await box.clear();
    db = (await LocalStore.instance.database())!;
  });
  tearDown(() async {
    box.applyOverride = null;
    await box.dispose();
    await box.clear();
  });
  Future<void> seed(String id, [int attempts = 9]) => pending
      .add(db, {
        'type': 'chatUpsert',
        'payload': {'id': id, 'groupId': 'g'},
        'attempts': attempts,
      })
      .then((_) {});

  for (final status in [400, 403, 408, 429, 500, 503]) {
    test(
      'swallowed HTTP $status retains the correct retry policy after many attempts',
      () async {
        final client = ForkOutboxHttpClient(
          MockClient((_) async => http.Response('{}', status)),
        );
        addTearDown(client.close);
        box.applyOverride = (_, _) async {
          await client.post(
            Uri.parse(
              'https://test.invalid/api/collections/chat_messages/records',
            ),
          );
          return false; // mirrors legacy service methods which swallow the error
        };
        await seed('message');
        await box.flush();
        final permanent = status == 400 || status == 403;
        expect(await pending.count(db), permanent ? 0 : 1);
        expect(await poison.count(db), permanent ? 1 : 0);
      },
    );
  }

  test(
    'network failures and unknown false results retry indefinitely',
    () async {
      for (final throwsError in [false, true]) {
        box.applyOverride = (_, _) async {
          if (throwsError) throw ClientException(statusCode: 0);
          return false;
        };
        await seed('message-$throwsError', 30);
        await box.flush();
        expect(await poison.count(db), 0);
      }
      expect(await pending.count(db), 2);
    },
  );

  test('parallel lanes do not share HTTP failure status', () async {
    final client = ForkOutboxHttpClient(
      MockClient((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return http.Response('{}', r.url.path.endsWith('bad') ? 400 : 503);
      }),
    );
    addTearDown(client.close);
    box.applyOverride = (_, p) async {
      await client.post(Uri.parse('https://test.invalid/${p['id']}'));
      return false;
    };
    await seed('bad');
    await seed('temporary');
    await box.flush();
    expect(await pending.count(db), 1);
    expect(
      (await pending.find(db)).single.value['payload'],
      containsPair('id', 'temporary'),
    );
    expect(await poison.count(db), 1);
  });

  for (final socket in [false, true]) {
    test(
      '${socket ? "socket reconnect" : "network restored"} retries previously poisoned operations',
      () async {
        final online = StreamController<bool>.broadcast();
        final reconnected = StreamController<void>.broadcast();
        addTearDown(online.close);
        addTearDown(reconnected.close);
        await poison.add(db, {
          'type': 'chatUpsert',
          'payload': {'id': 'old'},
          'attempts': 5,
        });
        var applied = 0;
        box.applyOverride = (_, _) async {
          applied++;
          return true;
        };
        await box.init(
          onlineChanges: online.stream,
          reconnected: reconnected.stream,
        );
        if (socket) {
          reconnected.add(null);
        } else {
          online.add(true);
        }
        for (
          var i = 0;
          i < 50 && (applied == 0 || box.poisonCount.value != 0);
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(applied, 1);
        expect(await poison.count(db), 0);
        expect(await pending.count(db), 0);
      },
    );
  }
}
