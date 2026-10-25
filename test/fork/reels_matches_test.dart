import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/http_client.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/reels/matches.dart';
import 'package:love_app/fork/reels/matches_ui.dart';

const group = 'pairaaaaaaaaaaa';

class Keys implements E2EKeyring {
  Keys(this.current);
  PairKey? current;
  final old = <String, PairKey>{};
  @override
  PairKey? currentKey(String groupId) => groupId == group ? current : null;
  @override
  PairKey? keyFor(String id) => current?.keyId == id ? current : old[id];
  @override
  String? groupWith(Set<String> members) => null;
}

void main() {
  late E2ECrypto crypto;
  setUpAll(() async => crypto = await E2ECrypto.init());
  late Keys keys;
  late RecordCodec codec;
  late ForkReelsMatches service;
  late List<Map<String, dynamic>> records;
  late bool failCreate, race;
  late Completer<void> barrier;
  late int readers, nextId, creates;
  setUp(() {
    keys = Keys(PairKey(group, 1, crypto.symmetricKey()));
    codec = RecordCodec(crypto, keys);
    records = [];
    failCreate = false;
    race = false;
    barrier = Completer<void>();
    readers = nextId = creates = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        final snapshot = List<Map<String, dynamic>>.of(records);
        if (race && snapshot.isEmpty && readers++ < 2) {
          if (readers == 2) barrier.complete();
          await barrier.future;
        }
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 500,
            'totalItems': snapshot.length,
            'totalPages': 1,
            'items': snapshot,
          }),
          200,
        );
      }
      creates++;
      if (failCreate) return http.Response('{}', 500);
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      if (records.any((record) => record['match_tag'] == body['match_tag']))
        return http.Response('{}', 400);
      final record = {
        ...body,
        'collectionName': ForkReelsMatches.collection,
        'created': '2026-10-23 12:00:00.000Z',
      };
      records.add(record);
      return http.Response(jsonEncode(record), 200);
    });
    final pb = PocketBase(
      'https://example.test',
      httpClientFactory: () => E2EHttpClient(
        client,
        codec: () async => codec,
        newId: () => 'match${(++nextId).toString().padLeft(10, '0')}',
      ),
    );
    service = ForkReelsMatches(
      pb: pb,
      codec: () async => codec,
      uid: () => 'aliceaaaaaaaaaa',
    );
  });

  test('wire stores ciphertext, list decrypts clip and reaction', () async {
    await service.save(group, 'shorts:abcdefghijk', '❤️');
    expect(records, hasLength(1));
    expect(records.single['state'], startsWith(e2eFieldPrefix));
    expect(jsonEncode(records), isNot(contains('abcdefghijk')));
    expect(jsonEncode(records), isNot(contains('❤️')));
    expect(records.single['match_tag'], matches(RegExp(r'^[a-f0-9]{64}$')));
    final saved = (await service.list(group)).single;
    expect(saved.link!.key, 'shorts:abcdefghijk');
    expect(saved.reaction, '❤️');
  });

  test(
    'repeat and pair key rotation do not duplicate a readable match',
    () async {
      await service.save(group, 'shorts:abcdefghijk', '🔥');
      keys.old[keys.current!.keyId] = keys.current!;
      keys.current = PairKey(group, 2, crypto.symmetricKey());
      await service.save(group, 'shorts:abcdefghijk', '❤️');
      expect(records, hasLength(1));
      expect(creates, 1);
    },
  );

  test('two simultaneous phones converge through the unique tag', () async {
    race = true;
    await Future.wait([
      service.save(group, 'shorts:abcdefghijk', '❤️'),
      service.save(group, 'shorts:abcdefghijk', '❤️'),
    ]);
    expect(creates, 2);
    expect(records, hasLength(1));
  });

  test(
    'failed write propagates; missing keys and unsafe input never create',
    () async {
      failCreate = true;
      await expectLater(
        service.save(group, 'shorts:abcdefghijk', '❤️'),
        throwsA(isA<ClientException>()),
      );
      expect(records, isEmpty);
      keys.current = null;
      await expectLater(
        service.save(group, 'shorts:abcdefghijk', '❤️'),
        throwsStateError,
      );
      await expectLater(
        service.save(group, '<script>', '❤️'),
        throwsArgumentError,
      );
      await expectLater(
        service.save(group, 'shorts:abcdefghijk', '<svg>'),
        throwsArgumentError,
      );
      expect(creates, 1);
    },
  );

  test('a record without local keys stays visible as locked', () async {
    await service.save(group, 'shorts:abcdefghijk', '❤️');
    keys.current = null;
    final entry = (await service.list(group)).single;
    expect(entry.locked, isTrue);
    expect(entry.link, isNull);
  });

  testWidgets(
    'load error offers retry and is distinct from an empty collection',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ForkReelsMatchesScreen(
            groupId: group,
            load: () async {
              if (calls++ == 0) throw StateError('offline');
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('long links and locked records fit narrow large-text layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    try {
      final items = [
        ForkReelMatch.fromRecord(
          RecordModel.fromJson({
            'id': 'open',
            'state': {
              'clip': 'shorts:abcdefghijklmnopqrstuvwxyz0123456789',
              'reaction': '❤️',
              'at': 1760000000000,
            },
          }),
        ),
        ForkReelMatch.fromRecord(
          RecordModel.fromJson({'id': 'locked', 'state': 'ciphertext'}),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ForkReelsMatchesScreen(groupId: group, load: () async => items),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);
      final locked = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data == 'Ролик закрыт' || widget.data == 'Clip is locked'),
      );
      await tester.scrollUntilVisible(locked, 200);
      expect(locked, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('D5: совпадение — карточкой с реакцией и «В воспоминания»', (
    tester,
  ) async {
    final saved = <String>[];
    final items = [
      ForkReelMatch.fromRecord(
        RecordModel.fromJson({
          'id': 'm1',
          'state': {
            'clip': 'shorts:abcdefghijk',
            'reaction': '🔥',
            'at': 1760000000000,
          },
        }),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ForkReelsMatchesScreen(
          groupId: group,
          load: () async => items,
          keep: ({required groupId, required key}) async {
            saved.add('$groupId|$key');
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('🔥'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    expect(saved, ['$group|shorts:abcdefghijk']);
    expect(tester.takeException(), isNull);
  });
}
