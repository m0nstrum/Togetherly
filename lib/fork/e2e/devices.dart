/// Ключи аккаунта и устройств, подписанный список устройств, доставка ключа
/// пары (docs/fork/E2E.md §5, §6).
///
/// Сервер хранит и раздаёт всё это, но подделать не может: список подписан
/// ключом аккаунта, которого у сервера нет, версия не даёт откатить список, а
/// ключ пары адресован конкретному устройству и подписан отправителем.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';
import 'envelope.dart';

/// Устройство целиком или только веб-комнаты (браузер, §10.1): ключи пары
/// на него не шифруются никогда.
enum DeviceKind { full, rooms }

class DeviceEntry {
  const DeviceEntry({
    required this.id,
    required this.boxKey,
    required this.signKey,
    this.kind = DeviceKind.full,
  });

  final String id;

  /// X25519: сюда шифруются ключи пары.
  final Uint8List boxKey;

  /// Ed25519: им устройство подписывает выдачу ключей.
  final Uint8List signKey;
  final DeviceKind kind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'box': b64(boxKey),
    'sign': b64(signKey),
    'kind': kind.name,
  };

  factory DeviceEntry.fromJson(Map<String, dynamic> j) => DeviceEntry(
    id: j['id'] as String,
    boxKey: unb64(j['box'] as String),
    signKey: unb64(j['sign'] as String),
    kind: DeviceKind.values.byName(j['kind'] as String),
  );
}

/// Список устройств аккаунта `{user, version, devices, sig}`.
class DeviceList {
  DeviceList({
    required this.user,
    required this.version,
    required this.devices,
    required this.sig,
  });

  final String user;
  final int version;
  final List<DeviceEntry> devices;
  final Uint8List sig;

  static Uint8List signedBytes(
    String user,
    int version,
    List<DeviceEntry> devices,
  ) => frame([
    utf8Bytes('tethered-devices-v1'),
    utf8Bytes(
      canonicalJson({
        'user': user,
        'version': version,
        'devices': devices.map((d) => d.toJson()).toList(),
      }),
    ),
  ]);

  static DeviceList create(
    E2ECrypto c,
    KeyPair account,
    String user,
    int version,
    List<DeviceEntry> devices,
  ) => DeviceList(
    user: user,
    version: version,
    devices: List.unmodifiable(devices),
    sig: c.sign(signedBytes(user, version, devices), account.secretKey),
  );

  /// Проверка списка партнёра: подпись его ключом аккаунта, тот же user и
  /// версия не ниже уже виденной (откат — подмена сервером).
  void verify(
    E2ECrypto c,
    Uint8List accountKey, {
    required String user,
    int seenVersion = 0,
  }) {
    if (this.user != user) {
      throw E2EVerifyError('список устройств чужого аккаунта');
    }
    if (!c.verify(signedBytes(user, version, devices), sig, accountKey)) {
      throw E2EVerifyError('подпись списка устройств не сходится');
    }
    if (version < seenVersion) {
      throw E2EVerifyError(
        'список устройств откатили: $version < $seenVersion',
      );
    }
  }

  DeviceEntry? device(String id) {
    for (final d in devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'user': user,
    'version': version,
    'devices': devices.map((d) => d.toJson()).toList(),
    'sig': b64(sig),
  };

  factory DeviceList.fromJson(Map<String, dynamic> j) => DeviceList(
    user: j['user'] as String,
    version: j['version'] as int,
    devices: [
      for (final d in j['devices'] as List)
        DeviceEntry.fromJson((d as Map).cast<String, dynamic>()),
    ],
    sig: unb64(j['sig'] as String),
  );
}

/// Ключи этого устройства.
class DeviceKeys {
  DeviceKeys({required this.id, required this.box, required this.sign});

  final String id;
  final KeyPair box;
  final KeyPair sign;

  DeviceEntry entry({DeviceKind kind = DeviceKind.full}) => DeviceEntry(
    id: id,
    boxKey: box.publicKey,
    signKey: sign.publicKey,
    kind: kind,
  );

  static DeviceKeys generate(E2ECrypto c, String id) =>
      DeviceKeys(id: id, box: c.boxKeyPair(), sign: c.signKeyPair());
}

/// Ключ пары, выданный устройству: sealed box на его X25519 и подпись
/// устройства-отправителя (sealed box сам по себе анонимен).
class PairKeyGrant {
  PairKeyGrant({
    required this.groupId,
    required this.epoch,
    required this.toDevice,
    required this.fromUser,
    required this.fromDevice,
    required this.sealed,
    required this.sig,
  });

  final String groupId;
  final int epoch;
  final String toDevice;
  final String fromUser;
  final String fromDevice;
  final Uint8List sealed;
  final Uint8List sig;

  static Uint8List _signed(
    String g,
    int e,
    String to,
    String fromUser,
    String fromDevice,
    Uint8List sealed,
  ) => frame([
    utf8Bytes('tethered-grant-v1'),
    utf8Bytes(g),
    utf8Bytes('$e'),
    utf8Bytes(to),
    utf8Bytes(fromUser),
    utf8Bytes(fromDevice),
    sealed,
  ]);

  /// Выдать [key] устройству [to]. Устройства «только комнаты» ключ пары не
  /// получают.
  static PairKeyGrant issue(
    E2ECrypto c,
    PairKey key,
    DeviceEntry to,
    String fromUser,
    DeviceKeys from,
  ) {
    if (to.kind != DeviceKind.full) {
      throw ArgumentError('устройству ${to.id} ключ пары не положен');
    }
    final payload = utf8Bytes(
      canonicalJson({
        'group': key.groupId,
        'epoch': key.epoch,
        'key': b64(key.key.extractBytes()),
      }),
    );
    final sealed = c.seal(payload, to.boxKey);
    return PairKeyGrant(
      groupId: key.groupId,
      epoch: key.epoch,
      toDevice: to.id,
      fromUser: fromUser,
      fromDevice: from.id,
      sealed: sealed,
      sig: c.sign(
        _signed(key.groupId, key.epoch, to.id, fromUser, from.id, sealed),
        from.sign.secretKey,
      ),
    );
  }

  /// Открыть выданный ключ. [senders] — проверенный список устройств
  /// отправителя (свой или партнёра).
  PairKey open(E2ECrypto c, DeviceKeys me, DeviceList senders) {
    if (toDevice != me.id) {
      throw E2EVerifyError('ключ выдан другому устройству');
    }
    if (senders.user != fromUser) {
      throw E2EVerifyError('список устройств не того отправителя');
    }
    final from = senders.device(fromDevice);
    if (from == null || from.kind != DeviceKind.full) {
      throw E2EVerifyError('отправителя нет в подписанном списке устройств');
    }
    if (!c.verify(
      _signed(groupId, epoch, toDevice, fromUser, fromDevice, sealed),
      sig,
      from.signKey,
    )) {
      throw E2EVerifyError('подпись выдачи ключа не сходится');
    }
    final j =
        jsonDecode(utf8.decode(c.sealOpen(sealed, me.box)))
            as Map<String, dynamic>;
    if (j['group'] != groupId || j['epoch'] != epoch) {
      throw E2EVerifyError('внутри другой ключ, чем снаружи');
    }
    return PairKey(groupId, epoch, c.keyFromBytes(unb64(j['key'] as String)));
  }

  Map<String, dynamic> toJson() => {
    'group': groupId,
    'epoch': epoch,
    'to_device': toDevice,
    'from_user': fromUser,
    'from_device': fromDevice,
    'sealed': b64(sealed),
    'sig': b64(sig),
  };

  factory PairKeyGrant.fromJson(Map<String, dynamic> j) => PairKeyGrant(
    groupId: j['group'] as String,
    epoch: j['epoch'] as int,
    toDevice: j['to_device'] as String,
    fromUser: j['from_user'] as String,
    fromDevice: j['from_device'] as String,
    sealed: unb64(j['sealed'] as String),
    sig: unb64(j['sig'] as String),
  );
}

/// Подтверждение приглашения по ссылке или QR (§6.2): MAC секретом из
/// фрагмента ссылки над ключом аккаунта принимающего. Список устройств им
/// подписан, поэтому MAC над ключом аккаунта покрывает и устройства.
abstract final class InviteProof {
  static Uint8List _msg(Uint8List accountKey) =>
      frame([utf8Bytes('tethered-invite-v1'), accountKey]);

  static Uint8List make(E2ECrypto c, SecureKey secret, Uint8List accountKey) =>
      c.mac(_msg(accountKey), secret);

  static bool valid(
    E2ECrypto c,
    SecureKey secret,
    Uint8List accountKey,
    Uint8List tag,
  ) => c.macVerify(_msg(accountKey), tag, secret);
}

/// Короткий отпечаток ключа аккаунта для фрагмента ссылки (`f=`): 128 бит.
Uint8List accountFingerprint(E2ECrypto c, Uint8List accountKey) =>
    c.hash(frame([utf8Bytes('tethered-ak-v1'), accountKey]), outLen: 16);

/// Полный отпечаток пары для QR (§6.3): 256 бит, порядок ключей не важен.
Uint8List pairFingerprint(E2ECrypto c, Uint8List accountA, Uint8List accountB) {
  final ab = _compare(accountA, accountB) <= 0;
  return c.hash(
    frame([
      utf8Bytes('tethered-fp-v1'),
      ab ? accountA : accountB,
      ab ? accountB : accountA,
    ]),
  );
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
