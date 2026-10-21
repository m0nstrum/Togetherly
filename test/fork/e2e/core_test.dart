// fork: ядро E2E (docs/fork/E2E.md, PLAN S8) на настоящей libsodium.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/devices.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/sas.dart';
import 'package:love_app/fork/e2e/sas_emoji.dart';

void main() {
  late E2ECrypto c;
  setUpAll(() async => c = await E2ECrypto.init());

  group('конверт', () {
    const place = RecordPlace('chat_messages', 'rec1', 'enc');

    test('туда и обратно', () {
      final k = PairKey('g1', 1, c.symmetricKey());
      final cipher = EnvelopeCipher(c);
      final e = cipher.seal({'text': 'привет'}, k, place);
      final back = Envelope.fromJson(e.toJson());
      expect(cipher.open(back, (id) => id == k.keyId ? k : null, place), {
        'text': 'привет',
      });
    });

    test('AAD: другая запись, поле или пара — не открывается', () {
      final k = PairKey('g1', 1, c.symmetricKey());
      final cipher = EnvelopeCipher(c);
      final e = cipher.seal({'text': 'x'}, k, place);
      for (final other in const [
        RecordPlace('chat_messages', 'rec2', 'enc'),
        RecordPlace('memories', 'rec1', 'enc'),
        RecordPlace('chat_messages', 'rec1', 'enc2'),
        ChannelPlace('pair:g1', 'typing', 0),
      ]) {
        expect(
          () => cipher.open(e, (_) => k, other),
          throwsA(isA<E2EVerifyError>()),
        );
      }
      // Тот же ключ, выданный другой паре: key_id в AAD.
      final relabeled = Envelope(keyId: 'g2:1', nonce: e.nonce, ct: e.ct);
      expect(
        () => cipher.open(relabeled, (_) => k, place),
        throwsA(isA<E2EVerifyError>()),
      );
    });

    test('изменённый шифртекст и чужой ключ — ошибка', () {
      final k = PairKey('g1', 1, c.symmetricKey());
      final cipher = EnvelopeCipher(c);
      final e = cipher.seal({'text': 'x'}, k, place);
      final ct = Uint8List.fromList(e.ct)..[0] ^= 1;
      expect(
        () => cipher.open(
          Envelope(keyId: e.keyId, nonce: e.nonce, ct: ct),
          (_) => k,
          place,
        ),
        throwsA(isA<E2EVerifyError>()),
      );
      final other = PairKey('g1', 1, c.symmetricKey());
      expect(
        () => cipher.open(e, (_) => other, place),
        throwsA(isA<E2EVerifyError>()),
      );
      expect(
        () => cipher.open(e, (_) => null, place),
        throwsA(isA<E2EVerifyError>()),
      );
    });

    test('неизвестная версия не читается', () {
      final j = EnvelopeCipher(
        c,
      ).seal({}, PairKey('g', 1, c.symmetricKey()), place).toJson();
      expect(
        () => Envelope.fromJson({...j, 'enc_v': 2}),
        throwsFormatException,
      );
    });
  });

  group('список устройств', () {
    test('подпись, откат, подмена', () {
      final ak = c.signKeyPair();
      final d1 = DeviceKeys.generate(c, 'd1');
      final list = DeviceList.create(c, ak, 'u1', 3, [d1.entry()]);
      final parsed = DeviceList.fromJson(list.toJson());
      parsed.verify(c, ak.publicKey, user: 'u1', seenVersion: 3);

      expect(
        () => parsed.verify(c, ak.publicKey, user: 'u1', seenVersion: 4),
        throwsA(isA<E2EVerifyError>()),
      );
      expect(
        () => parsed.verify(c, ak.publicKey, user: 'u2'),
        throwsA(isA<E2EVerifyError>()),
      );

      // Сервер дописал своё устройство — подпись не сходится.
      final evil = DeviceKeys.generate(c, 'evil');
      final forged = DeviceList(
        user: 'u1',
        version: 3,
        devices: [d1.entry(), evil.entry()],
        sig: list.sig,
      );
      expect(
        () => forged.verify(c, ak.publicKey, user: 'u1'),
        throwsA(isA<E2EVerifyError>()),
      );

      // Подписал чужим ключом аккаунта.
      final other = DeviceList.create(c, c.signKeyPair(), 'u1', 3, [
        d1.entry(),
      ]);
      expect(
        () => other.verify(c, ak.publicKey, user: 'u1'),
        throwsA(isA<E2EVerifyError>()),
      );
    });
  });

  group('выдача ключа пары', () {
    test('устройство партнёра получает ключ', () {
      final akA = c.signKeyPair(), akB = c.signKeyPair();
      final a = DeviceKeys.generate(c, 'a1'), b = DeviceKeys.generate(c, 'b1');
      final listA = DeviceList.create(c, akA, 'ua', 1, [a.entry()]);
      final listB = DeviceList.create(c, akB, 'ub', 1, [b.entry()]);
      listB.verify(c, akB.publicKey, user: 'ub');

      final key = PairKey('g1', 1, c.symmetricKey());
      final grant = PairKeyGrant.fromJson(
        PairKeyGrant.issue(c, key, listB.device('b1')!, 'ua', a).toJson(),
      );

      listA.verify(c, akA.publicKey, user: 'ua');
      final got = grant.open(c, b, listA);
      expect(got.keyId, 'g1:1');
      expect(got.key.extractBytes(), key.key.extractBytes());
    });

    test('подделки отклоняются', () {
      final akA = c.signKeyPair();
      final a = DeviceKeys.generate(c, 'a1'), b = DeviceKeys.generate(c, 'b1');
      final listA = DeviceList.create(c, akA, 'ua', 1, [a.entry()]);
      final key = PairKey('g1', 1, c.symmetricKey());

      // Сервер выдал свой ключ от имени устройства, которого нет в списке A.
      final server = DeviceKeys.generate(c, 'srv');
      final fake = PairKeyGrant.issue(c, key, b.entry(), 'ua', server);
      expect(() => fake.open(c, b, listA), throwsA(isA<E2EVerifyError>()));

      // Подпись настоящая, но эпоху снаружи подменили.
      final g = PairKeyGrant.issue(c, key, b.entry(), 'ua', a);
      final shifted = PairKeyGrant.fromJson({...g.toJson(), 'epoch': 2});
      expect(() => shifted.open(c, b, listA), throwsA(isA<E2EVerifyError>()));

      // Чужому устройству не открыть.
      final c2 = DeviceKeys.generate(c, 'b1');
      expect(() => g.open(c, c2, listA), throwsA(isA<E2EVerifyError>()));
    });

    test('устройству «только комнаты» ключ пары не выдаётся', () {
      final a = DeviceKeys.generate(c, 'a1');
      final browser = DeviceKeys.generate(
        c,
        'web',
      ).entry(kind: DeviceKind.rooms);
      expect(
        () => PairKeyGrant.issue(
          c,
          PairKey('g', 1, c.symmetricKey()),
          browser,
          'ua',
          a,
        ),
        throwsArgumentError,
      );
    });
  });

  group('приглашение по ссылке', () {
    test('MAC секретом из фрагмента ловит подмену ключа', () {
      final secret = c.symmetricKey();
      final akB = c.signKeyPair().publicKey;
      final tag = InviteProof.make(c, secret, akB);
      expect(InviteProof.valid(c, secret, akB, tag), isTrue);
      expect(
        InviteProof.valid(c, secret, c.signKeyPair().publicKey, tag),
        isFalse,
      );
      expect(InviteProof.valid(c, c.symmetricKey(), akB, tag), isFalse);
    });
  });

  group('сверка эмодзи', () {
    test('честный обмен: у обоих одинаковые 7 эмодзи', () {
      final akA = c.signKeyPair().publicKey, akB = c.signKeyPair().publicKey;
      final ini = SasInitiator(c, myAccount: akA, theirAccount: akB);
      final res = SasResponder(
        c,
        myAccount: akB,
        theirAccount: akA,
        commitment: ini.commitment,
      );
      final (reveal, codeA) = ini.onAccept(res.ephemeral);
      final codeB = res.onReveal(reveal);
      expect(codeA, codeB);
      expect(codeA.indices, hasLength(7));
      expect(codeA.indices.every((i) => i >= 0 && i < 64), isTrue);
    });

    test('сервер подменил ключ аккаунта — эмодзи расходятся', () {
      final akA = c.signKeyPair().publicKey, akB = c.signKeyPair().publicKey;
      final fakeB = c.signKeyPair().publicKey,
          fakeA = c.signKeyPair().publicKey;
      // A видит fakeB, B видит fakeA; посредник ведёт две сверки.
      final iniA = SasInitiator(c, myAccount: akA, theirAccount: fakeB);
      final mitmToA = SasResponder(
        c,
        myAccount: fakeB,
        theirAccount: akA,
        commitment: iniA.commitment,
      );
      final (revealA, codeA) = iniA.onAccept(mitmToA.ephemeral);
      mitmToA.onReveal(revealA);

      final mitmToB = SasInitiator(c, myAccount: fakeA, theirAccount: akB);
      final resB = SasResponder(
        c,
        myAccount: akB,
        theirAccount: fakeA,
        commitment: mitmToB.commitment,
      );
      final (revealM, _) = mitmToB.onAccept(resB.ephemeral);
      final codeB = resB.onReveal(revealM);
      expect(codeA == codeB, isFalse);
    });

    test('раскрытый ключ не совпал с коммитментом — ошибка', () {
      final akA = c.signKeyPair().publicKey, akB = c.signKeyPair().publicKey;
      final ini = SasInitiator(c, myAccount: akA, theirAccount: akB);
      final res = SasResponder(
        c,
        myAccount: akB,
        theirAccount: akA,
        commitment: ini.commitment,
      );
      expect(
        () => res.onReveal(c.kxKeyPair().publicKey),
        throwsA(isA<E2EVerifyError>()),
      );
    });

    test('биты в эмодзи: старшие первыми, как в Matrix', () {
      // 0b000001 000010 000011 000100 000101 000110 000111 + 6 бит хвоста
      final b = Uint8List.fromList([0x04, 0x20, 0xC4, 0x14, 0x61, 0xC0]);
      expect(SasCode.fromBytes(b).indices, [1, 2, 3, 4, 5, 6, 7]);
      expect(
        SasCode.fromBytes(Uint8List.fromList(List.filled(6, 0xFF))).indices,
        List.filled(7, 63),
      );
    });

    test('таблица: 64 эмодзи, названия различимы на слух', () {
      expect(sasEmoji, hasLength(64));
      expect(sasEmoji.map((e) => e.ru.toLowerCase()).toSet(), hasLength(64));
      expect(sasEmoji.map((e) => e.en.toLowerCase()).toSet(), hasLength(64));
      expect(sasEmoji.map((e) => e.symbol).toSet(), hasLength(64));
    });
  });

  test('отпечаток пары не зависит от порядка', () {
    final a = c.signKeyPair().publicKey, b = c.signKeyPair().publicKey;
    expect(pairFingerprint(c, a, b), pairFingerprint(c, b, a));
    expect(pairFingerprint(c, a, b), hasLength(32));
  });
}
