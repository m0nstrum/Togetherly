import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/http_client.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/movies/movie_choices.dart';
import 'package:love_app/services/movie_search_service.dart';

const group = 'pairaaaaaaaaaaa',
    alice = 'aliceaaaaaaaaaa',
    bob = 'bobbbbbbbbbbbbb';

class Keys implements E2EKeyring {
  Keys(this.current);
  PairKey? current;
  final old = <String, PairKey>{};
  @override
  PairKey? currentKey(String value) => value == group ? current : null;
  @override
  PairKey? keyFor(String value) =>
      current?.keyId == value ? current : old[value];
  @override
  String? groupWith(Set<String> members) => null;
}

void main() {
  late E2ECrypto crypto;
  setUpAll(() async => crypto = await E2ECrypto.init());
  late Keys keys;
  late RecordCodec codec;
  late ForkMovieChoices a, b;
  late List<Map<String, dynamic>> records;
  late bool failed, allowed;
  late int generated, writes;
  final movie = ForkMovieCard.fromResult(
    const MovieResult(id: 10, title: 'Matrix', year: '1999', kind: 'movie'),
  );
  setUp(() {
    keys = Keys(PairKey(group, 1, crypto.symmetricKey()));
    codec = RecordCodec(crypto, keys);
    records = [];
    failed = false;
    allowed = true;
    generated = writes = 0;
    final inner = MockClient((request) async {
      if (request.method == 'GET') {
        final sorted = List<Map<String, dynamic>>.of(records)
          ..sort(
            (a, b) =>
                (b['updated'] as String).compareTo(a['updated'] as String),
          );
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 500,
            'totalItems': sorted.length,
            'totalPages': 1,
            'items': sorted,
          }),
          200,
        );
      }
      writes++;
      if (failed) return http.Response('{}', 500);
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      final now = DateTime.utc(2026, 10, 23, 12, 0, writes).toIso8601String();
      if (request.method == 'POST') {
        if (records.any(
          (r) =>
              r['author_uid'] == body['author_uid'] &&
              r['movie_tag'] == body['movie_tag'],
        ))
          return http.Response('{}', 400);
        final record = {
          ...body,
          'collectionName': ForkMovieChoices.collection,
          'created': now,
          'updated': now,
        };
        records.add(record);
        return http.Response(jsonEncode(record), 200);
      }
      final i = records.indexWhere(
        (r) => r['id'] == request.url.pathSegments.last,
      );
      if (i < 0) return http.Response('{}', 404);
      records[i] = {...records[i], ...body, 'updated': now};
      return http.Response(jsonEncode(records[i]), 200);
    });
    final pb = PocketBase(
      'https://example.test',
      httpClientFactory: () => E2EHttpClient(
        inner,
        codec: () async => codec,
        newId: () => 'movie${(++generated).toString().padLeft(10, '0')}',
      ),
    );
    a = ForkMovieChoices(
      pb: pb,
      codec: () async => codec,
      uid: () => alice,
      canWrite: (_) => allowed,
    );
    b = ForkMovieChoices(
      pb: pb,
      codec: () async => codec,
      uid: () => bob,
      canWrite: (_) => allowed,
    );
  });

  test(
    'proposal, independent votes and undo use ciphertext and create matches only for two yes votes',
    () async {
      await a.propose(group, movie);
      expect((await a.list(group)).single!.vote, isNull);
      await a.vote(group, movie, true);
      expect(
        ForkMoviePicks(
          (await a.list(group)).whereType<ForkMovieChoice>().toList(),
          alice,
          bob,
        ).matches,
        isEmpty,
      );
      await b.vote(group, movie, true);
      final picks = ForkMoviePicks(
        (await a.list(group)).whereType<ForkMovieChoice>().toList(),
        alice,
        bob,
      );
      expect(picks.matches.single.key, movie.key);
      expect(records, hasLength(2));
      expect(jsonEncode(records), isNot(contains('Matrix')));
      expect(records.every((record) => isSealedValue(record['state'])), isTrue);
      expect(records[0]['movie_tag'], records[1]['movie_tag']);
      await a.propose(group, movie);
      expect(
        (await a.list(
          group,
        )).firstWhere((choice) => choice!.author == alice)!.vote,
        isTrue,
      );
      await a.vote(group, movie, false);
      expect(
        ForkMoviePicks(
          (await a.list(group)).whereType<ForkMovieChoice>().toList(),
          alice,
          bob,
        ).matches,
        isEmpty,
      );
      await a.vote(group, movie, null);
      expect(
        ForkMoviePicks(
          (await a.list(group)).whereType<ForkMovieChoice>().toList(),
          alice,
          bob,
        ).pending.single.key,
        movie.key,
      );
    },
  );

  test(
    'pair-key rotation updates the same owned row without changing its tag',
    () async {
      await a.vote(group, movie, true);
      final id = records.single['id'], tag = records.single['movie_tag'];
      keys.old[keys.current!.keyId] = keys.current!;
      keys.current = PairKey(group, 2, crypto.symmetricKey());
      await a.vote(group, movie, false);
      expect(records, hasLength(1));
      expect(records.single['id'], id);
      expect(records.single['movie_tag'], tag);
      expect((await a.list(group)).single!.vote, isFalse);
    },
  );

  test(
    'server cannot relabel an encrypted choice as the other voter or another group',
    () async {
      await a.vote(group, movie, true);
      records.single['author_uid'] = bob;
      expect((await a.list(group)).single, isNull);
      records.single['author_uid'] = alice;
      records.single['group_id'] = 'other';
      expect((await a.list(group)).single, isNull);
    },
  );

  test(
    'missing keys or quarantined pair never writes; network failure propagates',
    () async {
      allowed = false;
      await expectLater(
        a.vote(group, movie, true),
        throwsA(isA<E2ENoKeyError>()),
      );
      expect(writes, 0);
      allowed = true;
      failed = true;
      await expectLater(
        a.vote(group, movie, true),
        throwsA(isA<ClientException>()),
      );
      expect(records, isEmpty);
      failed = false;
      keys.current = null;
      await expectLater(
        a.vote(group, movie, true),
        throwsA(isA<E2ENoKeyError>()),
      );
    },
  );

  test(
    'identity is locale-independent and unsafe metadata URLs are removed',
    () {
      final translated = ForkMovieCard.fromResult(
        const MovieResult(id: 10, title: 'Матрица', kind: 'movie'),
      );
      expect(translated.key, movie.key);
      final wiki = ForkMovieCard.fromResult(
        const MovieResult(
          id: 0,
          title: 'Film',
          kind: 'movie',
          link: 'https://www.wikidata.org/wiki/Q123/?tracking=1#x',
          posterUrl: 'javascript:alert(1)',
        ),
      );
      expect(wiki.info, 'https://wikidata.org/wiki/Q123');
      expect(wiki.key, 'url:https://wikidata.org/wiki/Q123');
      expect(wiki.poster, isNull);
      final choices = [
        ForkMovieChoice(
          id: 'a',
          author: alice,
          tag: 'a',
          movie: movie,
          vote: true,
        ),
        ForkMovieChoice(
          id: 'outsider',
          author: 'eve',
          tag: 'a',
          movie: movie,
          vote: true,
        ),
      ];
      expect(ForkMoviePicks(choices, alice, bob).matches, isEmpty);
    },
  );
  test('ciphertext length does not distinguish yes, no and undo', () async {
    await a.vote(group, movie, true);
    final yes = (records.single['state'] as String).length;
    await a.vote(group, movie, false);
    final no = (records.single['state'] as String).length;
    await a.vote(group, movie, null);
    final pending = (records.single['state'] as String).length;
    expect([yes, no, pending], everyElement(yes));
  });
}
