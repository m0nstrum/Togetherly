import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/features/pet_home/pet_home_model.dart';
import 'package:love_app/features/pet_home/pet_home_repository.dart';

const group = 'pairaaaaaaaaaaa';

class Keys implements E2EKeyring {
  Keys(this.key);
  PairKey? key;
  @override
  PairKey? currentKey(String g) => g == group ? key : null;
  @override
  PairKey? keyFor(String id) => key?.keyId == id ? key : null;
  @override
  String? groupWith(Set<String> members) => null;
}

void main() {
  late E2ECrypto crypto;
  setUpAll(() async {
    crypto = await E2ECrypto.init();
  });
  late Keys keys;
  late RecordCodec codec;
  late Map<String, dynamic> stored;
  late PetHomeRepository repo;
  late String uid;
  late bool conflict, lostResponse;
  late int writes;
  setUp(() {
    keys = Keys(PairKey(group, 1, crypto.symmetricKey()));
    codec = RecordCodec(crypto, keys);
    stored = {'group_id': group, 'revision': 0};
    uid = 'alice';
    conflict = lostResponse = false;
    writes = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET')
        return http.Response(jsonEncode(stored), 200);
      writes++;
      final body = jsonDecode(request.body) as Map;
      expect(body['state'], startsWith('e2e1.'));
      expect(request.body, isNot(contains('cottage')));
      if (conflict) {
        conflict = false;
        final partner = PetHome()..furnish('monstera');
        stored = {
          'id': 'record1',
          'group_id': group,
          'revision': 1,
          ...codec.encode('pet_homes', group, group, {
            'group_id': group,
            'state': {'group': group, 'home': partner.toJson()},
          }),
        };
        return http.Response('{}', 409);
      }
      stored = {
        'id': 'record1',
        'group_id': group,
        'revision': (stored['revision'] as int) + 1,
        'state': body['state'],
      };
      if (lostResponse) {
        lostResponse = false;
        throw http.ClientException('dropped response');
      }
      return http.Response(jsonEncode(stored), 200);
    });
    repo = PetHomeRepository(
      pb: PocketBase('https://example.test', httpClientFactory: () => client),
      codec: () async => codec,
      uid: () => uid,
    );
  });

  test('ciphertext roundtrip and rebasing preserve partner purchase', () async {
    conflict = true;
    final result = await repo.change(group, (home) => home.furnish('frame'));
    expect(writes, 2);
    expect(result.home.owned, containsAll(['monstera', 'frame']));
    expect(result.home.balance, 18);
    final wire = jsonEncode(stored);
    expect(wire, isNot(contains('monstera')));
    expect((await repo.load(group)).home.toJson(), result.home.toJson());
  });
  test('lost response and repeated operation do not double reward', () async {
    lostResponse = true;
    const op = '0123456789abcdef0123456789abcdef';
    final result = await repo.change(
      group,
      (h) => h.careFor(PetCare.feed, uid, 1),
      operation: op,
    );
    expect(result.home.balance, 45);
    final retry = await repo.change(
      group,
      (h) => h.careFor(PetCare.feed, uid, 2),
      operation: op,
    );
    expect(retry.home.care['feed'], 1);
    expect(writes, 1);
  });
  test('missing key and plaintext fail closed without overwriting', () async {
    await repo.change(group, (h) => h.furnish('frame'));
    keys.key = null;
    await expectLater(repo.load(group), throwsA(isA<E2ENoKeyError>()));
    await expectLater(
      repo.change(group, (h) => h.furnish('lamp')),
      throwsA(isA<E2ENoKeyError>()),
    );
    expect(writes, 1);
    stored['state'] = {'group': group, 'home': PetHome().toJson()};
    await expectLater(repo.load(group), throwsFormatException);
  });
  test(
    'session change during key load never posts previous account data',
    () async {
      final pb = repo.pb;
      final changed = PetHomeRepository(
        pb: pb,
        codec: () async {
          uid = 'bob';
          return codec;
        },
        uid: () => uid,
      );
      await expectLater(
        changed.change(group, (h) => h.furnish('frame')),
        throwsStateError,
      );
      expect(writes, 0);
    },
  );
  test('AAD rejects a copied home from another connection', () async {
    await repo.change(group, (h) => h.furnish('frame'));
    final raw = {...stored, 'group_id': 'other'};
    final opened = codec.decode('pet_homes', raw);
    expect(opened['state'], isNull);
  });
}
