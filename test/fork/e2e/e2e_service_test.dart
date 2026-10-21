// fork: обмен ключами пары (PLAN S8, критерий: две установки получают общий
// ключ пары, подмену ключа на сервере видно в состоянии для UI).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/devices.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/key_store.dart';

const alice = 'alice', bob = 'bob', group = 'g1';

/// Общая база «сервера».
class ServerDb {
  final identities = <String, Map<String, dynamic>>{};
  final grants = <String, (PairKeyGrant, String)>{};
  final handshakes = <HandshakeMsg>[];
  final members = <String, List<String>>{
    group: [alice, bob],
  };
  var _id = 0;

  /// Подмена: что отдать [viewer], когда он спрашивает ключи [uid].
  Map<String, dynamic>? Function(String viewer, String uid)? forge;
}

/// Как сервер выглядит для одного клиента.
class FakeBackend implements E2EBackend {
  FakeBackend(this.db, this.viewer);
  final ServerDb db;
  final String viewer;

  @override
  Future<IdentityRecord?> identity(String uid) async {
    final j = db.forge?.call(viewer, uid) ?? db.identities[uid];
    if (j == null) return null;
    return IdentityRecord(
      accountKey: unb64(j['ak'] as String),
      devices: DeviceList.fromJson(
        (j['devices'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  @override
  Future<void> putIdentity(String uid, Uint8List ak, DeviceList list) async {
    final old = db.identities[uid];
    if (old != null &&
        (old['devices'] as Map)['version'] as int >= list.version) {
      throw StateError('сервер: версия только вперёд');
    }
    db.identities[uid] = {'ak': b64(ak), 'devices': list.toJson()};
  }

  @override
  Future<List<String>> members(String groupId) async => db.members[groupId]!;

  @override
  Future<List<PairKeyGrant>> grantsTo(String uid, String deviceId) async => [
    for (final (g, to) in db.grants.values)
      if (to == uid && g.toDevice == deviceId) g,
  ];

  @override
  Future<void> putGrant(PairKeyGrant g, String toUid) async {
    db.grants.putIfAbsent(
      '${g.groupId}|${g.epoch}|${g.toDevice}',
      () => (g, toUid),
    );
  }

  @override
  Future<void> postHandshake(
    String groupId,
    String fromUid,
    String session,
    String kind,
    Map<String, dynamic> data,
  ) async {
    db.handshakes.add(
      HandshakeMsg(
        id: '${db._id++}',
        fromUid: fromUid,
        session: session,
        kind: kind,
        data: data,
        created: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<HandshakeMsg>> handshakes(String groupId) async =>
      List.of(db.handshakes);
}

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
    );
    await s.start();
    return s;
  }

  Future<void> syncBoth(E2EService a, E2EService b, [int rounds = 2]) async {
    for (var i = 0; i < rounds; i++) {
      await a.syncGroup(group);
      await b.syncGroup(group);
    }
  }

  List<int> keyBytes(E2EService s) => s.currentKey(group)!.key.extractBytes();

  test(
    'две установки получают общий ключ пары; без сверки — «не проверено»',
    () async {
      final db = ServerDb();
      final a = await install(db, alice);
      expect(await a.syncGroup(group), PairE2EStatus.waitingPartner);
      final b = await install(db, bob);
      await syncBoth(a, b);

      expect(a.currentKey(group)!.keyId, 'g1:1');
      expect(keyBytes(a), keyBytes(b));
      expect(a.status.value[group], PairE2EStatus.unverified);
      expect(b.status.value[group], PairE2EStatus.unverified);
    },
  );

  test('ссылка с секретом: обе стороны проверены автоматически', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    final frag = a.inviteFragment('ABC123');
    await b.acceptedInvite(group, 'ABC123', frag);
    await syncBoth(b, a);

    expect(keyBytes(a), keyBytes(b));
    expect(a.status.value[group], PairE2EStatus.verified);
    expect(b.status.value[group], PairE2EStatus.verified);
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
      await b.acceptedInvite(group, 'ABC123', frag);
      await syncBoth(b, a);

      expect(
        b.status.value[group],
        PairE2EStatus.tampered,
        reason: 'отпечаток в ссылке не совпал',
      );
      // Алиса подмену сама не видит: подтверждение Боба не пришло, а его
      // не отличить от приёма «по коду». Для неё — «не проверено».
      expect(a.status.value[group], PairE2EStatus.unverified);
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
    expect(a.status.value[group], PairE2EStatus.unverified);

    await a.sasStart(group, bob);
    await b.syncGroup(group);
    expect(b.sas.value, isA<SasIncoming>());
    await b.sasAccept();
    await a.syncGroup(group);
    await b.syncGroup(group);
    // У Боба коммитмент Алисы не сходится с тем, что он считает её ключом.
    expect(
      b.sas.value,
      isA<SasFinished>().having((s) => s.match, 'match', isFalse),
    );
    expect(b.status.value[group], isNot(PairE2EStatus.verified));
  });

  test('честная сверка эмодзи: одинаковые 7 эмодзи, «проверено»', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    await syncBoth(a, b);

    await a.sasStart(group, bob);
    await b.syncGroup(group);
    await b.sasAccept();
    await a.syncGroup(group);
    await b.syncGroup(group);
    final ca = a.sas.value, cb = b.sas.value;
    expect(ca, isA<SasShowCode>());
    expect(cb, isA<SasShowCode>());
    expect((ca as SasShowCode).code, (cb as SasShowCode).code);

    await a.sasConfirm(match: true);
    await b.sasConfirm(match: true);
    expect(a.status.value[group], PairE2EStatus.verified);
    expect(b.status.value[group], PairE2EStatus.verified);
  });

  test('«не совпадает» у партнёра обрывает сверку и у нас', () async {
    final db = ServerDb();
    final a = await install(db, alice);
    final b = await install(db, bob);
    await syncBoth(a, b);
    await a.sasStart(group, bob);
    await b.syncGroup(group);
    await b.sasAccept();
    await a.syncGroup(group);
    await b.syncGroup(group);
    await b.sasConfirm(match: false);
    await a.syncGroup(group);
    expect(
      a.sas.value,
      isA<SasFinished>().having((s) => s.match, 'match', isFalse),
    );
    expect(a.status.value[group], PairE2EStatus.unverified);
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
      expect(a.status.value[group], PairE2EStatus.keyChanged);
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
    await a.syncGroup(group);
    db.forge = (viewer, uid) => uid == bob ? old : null;
    expect(await a.syncGroup(group), PairE2EStatus.tampered);
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
      expect(a.status.value[group], PairE2EStatus.tampered);
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
    expect(a2.currentKey(group)!.key.extractBytes(), keyBytes(b));
    expect(await a2.syncGroup(group), PairE2EStatus.unverified);
    expect(
      db.identities[alice]!['devices']['version'],
      1,
      reason: 'то же устройство — список не растёт',
    );
  });
}
