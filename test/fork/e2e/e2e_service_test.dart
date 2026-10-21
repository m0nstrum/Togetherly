// fork: обмен ключами пары (PLAN S8, критерий: две установки получают общий
// ключ пары, подмену ключа на сервере видно в состоянии для UI).

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/devices.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/key_store.dart';

import 'fake_backend.dart';

void main() {
  late E2ECrypto c;
  setUpAll(() async => c = await E2ECrypto.init());

  Future<E2EService> install(
    ServerDb db,
    String uid, [
    MemoryVault? vault,
  ]) async {
    final s = E2EService(
      crypto: c,
      store: E2EKeyStore(c, vault ?? MemoryVault()),
      backend: FakeBackend(db, uid),
      uid: uid,
      kdfParams: const KdfParams(ops: 1, mem: 8 << 20),
    );
    await s.start();
    return s;
  }

  Future<void> syncBoth(E2EService a, E2EService b, [int rounds = 2]) async {
    for (var i = 0; i < rounds; i++) {
      await a.syncGroup(gid);
      await b.syncGroup(gid);
    }
  }

  List<int> keyBytes(E2EService s) => s.currentKey(gid)!.key.extractBytes();

  test(
    'две установки получают общий ключ пары; без сверки — «не проверено»',
    () async {
      final db = ServerDb();
      final a = await install(db, alice);
      expect(await a.syncGroup(gid), PairE2EStatus.waitingPartner);
      final b = await install(db, bob);
      await syncBoth(a, b);

      expect(a.currentKey(gid)!.keyId, 'g1:1');
      expect(keyBytes(a), keyBytes(b));
      expect(a.status.value[gid], PairE2EStatus.unverified);
      expect(b.status.value[gid], PairE2EStatus.unverified);
    },
  );

  test('ссылка с секретом: обе стороны проверены автоматически', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    final frag = a.inviteFragment('ABC123');
    await b.acceptedInvite(gid, 'ABC123', frag);
    await syncBoth(b, a);

    expect(keyBytes(a), keyBytes(b));
    expect(a.status.value[gid], PairE2EStatus.verified);
    expect(b.status.value[gid], PairE2EStatus.verified);
  });

  test(
    'ссылка с секретом: подмену ключей сервером видят обе стороны',
    () async {
      final db = ServerDb();
      final a = await install(db, alice);
      final b = await install(db, bob);
      // Сервер — посредник: каждому показывает поддельные ключи другого.
      final fakeAlice = await install(ServerDb(), alice);
      final fakeBob = await install(ServerDb(), bob);
      Map<String, dynamic> pub(E2EService s) => {
        'ak': b64(s.keys.account.publicKey),
        'devices': DeviceList.create(c, s.keys.account, s.uid, 1, [
          s.keys.device.entry(),
        ]).toJson(),
      };
      db.forge = (viewer, uid) =>
          viewer == uid ? null : pub(uid == alice ? fakeAlice : fakeBob);

      final frag = a.inviteFragment('ABC123');
      await b.acceptedInvite(gid, 'ABC123', frag);
      await syncBoth(b, a);

      expect(
        b.status.value[gid],
        PairE2EStatus.tampered,
        reason: 'отпечаток в ссылке не совпал',
      );
      // Алиса подмену сама не видит: подтверждение Боба не пришло, а его
      // не отличить от приёма «по коду». Для неё — «не проверено».
      expect(a.status.value[gid], PairE2EStatus.unverified);
    },
  );

  test('только код: подмену ловит сверка эмодзи', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    final fakeAlice = await install(ServerDb(), alice);
    final fakeBob = await install(ServerDb(), bob);
    Map<String, dynamic> pub(E2EService s) => {
      'ak': b64(s.keys.account.publicKey),
      'devices': DeviceList.create(c, s.keys.account, s.uid, 1, [
        s.keys.device.entry(),
      ]).toJson(),
    };
    db.forge = (viewer, uid) =>
        viewer == uid ? null : pub(uid == alice ? fakeAlice : fakeBob);
    await syncBoth(a, b);
    expect(a.status.value[gid], PairE2EStatus.unverified);

    await a.sasStart(gid, bob);
    await b.syncGroup(gid);
    expect(b.sas.value, isA<SasIncoming>());
    await b.sasAccept();
    await a.syncGroup(gid);
    await b.syncGroup(gid);
    // У Боба коммитмент Алисы не сходится с тем, что он считает её ключом.
    expect(
      b.sas.value,
      isA<SasFinished>().having((s) => s.match, 'match', isFalse),
    );
    expect(b.status.value[gid], isNot(PairE2EStatus.verified));
  });

  test('честная сверка эмодзи: одинаковые 7 эмодзи, «проверено»', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    await syncBoth(a, b);

    await a.sasStart(gid, bob);
    await b.syncGroup(gid);
    await b.sasAccept();
    await a.syncGroup(gid);
    await b.syncGroup(gid);
    final ca = a.sas.value, cb = b.sas.value;
    expect(ca, isA<SasShowCode>());
    expect(cb, isA<SasShowCode>());
    expect((ca as SasShowCode).code, (cb as SasShowCode).code);

    await a.sasConfirm(match: true);
    await b.sasConfirm(match: true);
    expect(a.status.value[gid], PairE2EStatus.verified);
    expect(b.status.value[gid], PairE2EStatus.verified);
  });

  test('«не совпадает» у партнёра обрывает сверку и у нас', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    await syncBoth(a, b);
    await a.sasStart(gid, bob);
    await b.syncGroup(gid);
    await b.sasAccept();
    await a.syncGroup(gid);
    await b.syncGroup(gid);
    await b.sasConfirm(match: false);
    await a.syncGroup(gid);
    expect(
      a.sas.value,
      isA<SasFinished>().having((s) => s.match, 'match', isFalse),
    );
    expect(a.status.value[gid], PairE2EStatus.unverified);
  });

  test(
    'переустановка партнёра без бэкапа — «ключ сменился», ключ пары доходит',
    () async {
      final db = ServerDb();
      final a = await install(db, alice);
      final b = await install(db, bob);
      await syncBoth(a, b);

      final b2 = await install(db, bob); // новый Keystore
      await syncBoth(a, b2);
      expect(a.status.value[gid], PairE2EStatus.keyChanged);
      expect(
        keyBytes(b2),
        keyBytes(a),
        reason: 'работает, но с громкой плашкой',
      );
    },
  );

  test('откат списка устройств сервером — подмена', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    await syncBoth(a, b);
    final old = Map<String, dynamic>.from(db.identities[bob]!);
    // Боб добавил устройство (версия 2), сервер отдаёт Алисе версию 1.
    final extra = DeviceKeys.generate(c, 'b2').entry();
    final v2 = DeviceList.create(c, b.keys.account, bob, 2, [
      b.keys.device.entry(),
      extra,
    ]);
    db.identities[bob] = {
      'ak': b64(b.keys.account.publicKey),
      'devices': v2.toJson(),
    };
    await a.syncGroup(gid);
    db.forge = (viewer, uid) => uid == bob ? old : null;
    expect(await a.syncGroup(gid), PairE2EStatus.tampered);
  });

  test(
    'сервер дописал своё устройство в список — ключ пары ему не выдаётся',
    () async {
      final db = ServerDb();
      final a = await install(db, alice);
      final b = await install(db, bob);
      final evil = DeviceKeys.generate(c, 'evil').entry();
      final j = db.identities[bob]!;
      final list = DeviceList.fromJson(
        (j['devices'] as Map).cast<String, dynamic>(),
      );
      db.forge = (viewer, uid) => uid != bob
          ? null
          : {
              'ak': j['ak'],
              'devices': DeviceList(
                user: bob,
                version: list.version,
                devices: [...list.devices, evil],
                sig: list.sig,
              ).toJson(),
            };
      await syncBoth(a, b);
      expect(a.status.value[gid], PairE2EStatus.tampered);
      expect(db.grants.keys.where((k) => k.endsWith('|evil')), isEmpty);
    },
  );

  test('ключи переживают перезапуск приложения', () async {
    final db = ServerDb();
    final vault = MemoryVault();
    final a = await install(db, alice, vault);
    final b = await install(db, bob);
    await syncBoth(a, b);
    final a2 = await install(db, alice, vault);
    expect(a2.currentKey(gid)!.key.extractBytes(), keyBytes(b));
    expect(await a2.syncGroup(gid), PairE2EStatus.unverified);
    expect(
      db.identities[alice]!['devices']['version'],
      1,
      reason: 'то же устройство — список не растёт',
    );
  });

  group('бэкап ключей', () {
    late List<String> words;
    setUpAll(
      () => words = File('assets/fork/bip39_english.txt').readAsLinesSync(),
    );

    test(
      'новый телефон: ждёт фразу, восстанавливает тот же ключ и историю',
      () async {
        final db = ServerDb();
        final a = await install(db, alice);
        final b = await install(db, bob);
        await syncBoth(a, b);
        final phrase = RecoveryPhrase.generate(c, words).toString();
        await a.enableBackup(BackupMethod.phrase, phrase);
        expect(a.backupMethod.value, BackupMethod.phrase);

        // Новый телефон Алисы: Keystore пуст, бэкап на сервере.
        final a2 = await install(db, alice);
        expect(a2.needsRestore.value, isTrue);
        expect(a2.restoreMethod, BackupMethod.phrase);
        expect(await a2.syncGroup(gid), PairE2EStatus.needsRestore);
        expect(
          db.identities[alice]!['devices']['version'],
          1,
          reason: 'до восстановления ключи не публикуются',
        );

        await expectLater(
          a2.restore(RecoveryPhrase.generate(c, words).toString()),
          throwsA(isA<E2EVerifyError>()),
        );
        await a2.restore(phrase.toUpperCase());
        expect(a2.needsRestore.value, isFalse);
        expect(a2.keys.account.publicKey, a.keys.account.publicKey);
        expect(
          a2.currentKey(gid)!.key.extractBytes(),
          keyBytes(b),
          reason: 'история читается',
        );

        // Партнёр не видит смены ключа: тот же ключ аккаунта, новое устройство.
        await syncBoth(b, a2);
        expect(b.status.value[gid], PairE2EStatus.unverified);
        expect((db.identities[alice]!['devices']['devices'] as List).length, 2);
      },
    );

    test('новый ключ пары сам попадает в бэкап', () async {
      final db = ServerDb()..members['g2'] = [alice, bob];
      final a = await install(db, alice);
      final b = await install(db, bob);
      await a.enableBackup(BackupMethod.password, 'Ябл0ко-Кит-Велик');
      await syncBoth(a, b);
      await a.syncGroup('g2');
      await b.syncGroup('g2');
      final back = KeyBackup.open(
        c,
        user: alice,
        data: db.backups[alice]!,
        secret: 'Ябл0ко-Кит-Велик',
      );
      expect({for (final k in back.pairKeys) k.keyId}, {'g1:1', 'g2:1'});
    });

    test(
      'без фразы — начать заново: новый ключ, партнёр видит смену',
      () async {
        final db = ServerDb();
        final a = await install(db, alice);
        final b = await install(db, bob);
        await syncBoth(a, b);
        await a.enableBackup(BackupMethod.password, 'Ябл0ко-Кит-Велик');
        final a2 = await install(db, alice);
        await a2.startFresh();
        expect(a2.keys.account.publicKey, isNot(a.keys.account.publicKey));
        expect(a2.backupMethod.value, isNull);
        await syncBoth(b, a2);
        expect(b.status.value[gid], PairE2EStatus.keyChanged);
      },
    );
  });

  group('ротация эпохи (§6.5)', () {
    test('участник ушёл — новая эпоха, ему не выдана', () async {
      const carol = 'carol';
      final db = ServerDb()..members[gid] = [alice, bob, carol];
      final a = await install(db, alice);
      final b = await install(db, bob);
      final cl = await install(db, carol);
      for (var i = 0; i < 2; i++) {
        for (final x in [a, b, cl]) {
          await x.syncGroup(gid);
        }
      }
      expect(keyBytes(cl), keyBytes(a));

      db.members[gid] = [alice, bob];
      await syncBoth(a, b);
      expect(a.currentKey(gid)!.epoch, 2);
      expect(keyBytes(b), keyBytes(a));
      expect(
        b.keyFor('g1:1'),
        isNotNull,
        reason: 'старые эпохи остаются для истории',
      );
      expect(
        db.grants.keys.where(
          (k) => k.startsWith('g1|2|') && k.endsWith(cl.keys.device.id),
        ),
        isEmpty,
      );
    });

    test('после сверки сменившегося ключа — новая эпоха у обоих', () async {
      final db = ServerDb();
      final a = await install(db, alice);
      final b = await install(db, bob);
      await syncBoth(a, b);
      final b2 = await install(db, bob); // переустановка без бэкапа
      await syncBoth(a, b2);
      expect(a.status.value[gid], PairE2EStatus.keyChanged);

      await a.sasStart(gid, bob);
      await b2.syncGroup(gid);
      await b2.sasAccept();
      await a.syncGroup(gid);
      await b2.syncGroup(gid);
      await a.sasConfirm(match: true);
      await b2.sasConfirm(match: true);
      await syncBoth(a, b2, 3);
      expect(a.currentKey(gid)!.epoch, 2);
      expect(keyBytes(b2), keyBytes(a));
      expect(a.status.value[gid], PairE2EStatus.verified);
    });

    test(
      'ротацию создаёт участник с наименьшим uid, остальные просят',
      () async {
        final db = ServerDb();
        final a = await install(db, alice);
        final b = await install(db, bob);
        await syncBoth(a, b);
        b.keys.rotateNeeded.add(gid);
        await b.syncGroup(gid);
        expect(
          b.currentKey(gid)!.epoch,
          1,
          reason: 'bob > alice — сам не ротирует',
        );
        expect(
          db.handshakes.where((m) => m.kind == 'rotate_request'),
          hasLength(1),
        );
        await syncBoth(a, b, 2);
        expect(a.currentKey(gid)!.epoch, 2);
        expect(keyBytes(b), keyBytes(a));
      },
    );
  });
}
