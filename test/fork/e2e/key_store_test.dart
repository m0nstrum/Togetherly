// fork: хранилище ключей E2E (docs/fork/E2E.md §5).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/key_store.dart';

void main() {
  late E2ECrypto c;
  setUpAll(() async => c = await E2ECrypto.init());

  test('ключи переживают перезапуск и работают', () async {
    final vault = MemoryVault();
    final store = E2EKeyStore(c, vault);
    expect(await store.load(), isNull);

    final k = E2EKeys.generate(c, 'dev1')
      ..pairKeys['g1:1'] = PairKey('g1', 1, c.symmetricKey())
      ..pairKeys['g1:2'] = PairKey('g1', 2, c.symmetricKey())
      ..peers['bob'] = PeerState(
        accountKey: c.signKeyPair().publicKey,
        seenVersion: 3,
      );
    await store.save(k);

    final back = (await E2EKeyStore(c, vault).load())!;
    expect(back.device.id, 'dev1');
    expect(back.currentKey('g1')!.epoch, 2);
    expect(back.peers['bob']!.seenVersion, 3);
    expect(back.peers['bob']!.verified, isFalse);

    // Подпись старым ключом аккаунта проверяется восстановленным публичным.
    final msg = utf8Bytes('x');
    expect(
      c.verify(msg, c.sign(msg, back.account.secretKey), k.account.publicKey),
      isTrue,
    );
    // Ключ пары тот же: шифр старым открывается новым.
    const place = RecordPlace('chat_messages', 'r', 'enc');
    final e = EnvelopeCipher(c).seal({'t': 1}, k.pairKeys['g1:1']!, place);
    expect(EnvelopeCipher(c).open(e, back.keyFor, place), {'t': 1});
    // Sealed box на ключ устройства открывается восстановленным.
    expect(
      c.sealOpen(c.seal(msg, k.device.box.publicKey), back.device.box),
      msg,
    );

    await store.wipe();
    expect(await store.load(), isNull);
  });
}
