/// Ключи этого устройства в Keystore (docs/fork/E2E.md §5).
///
/// Всё лежит одной записью: ключ аккаунта, ключи устройства, ключи пар по
/// `key_id` и что известно о партнёрах (их ключ аккаунта, виденная версия
/// списка устройств, проверен ли). Отдельное хранилище от сессии
/// (secure_auth_store.dart) и без `resetOnError`: молча стёртые ключи — это
/// потерянная история; при ошибке человеку предлагают восстановиться из
/// бэкапа.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto.dart';
import 'devices.dart';
import 'envelope.dart';

/// Где лежат байты. В тестах — [MemoryVault].
abstract interface class KeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageVault implements KeyVault {
  const SecureStorageVault();

  static const FlutterSecureStorage _s = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryVault implements KeyVault {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Что устройство знает о партнёре.
class PeerState {
  PeerState({
    required this.accountKey,
    this.seenVersion = 0,
    this.verified = false,
    this.keyChanged = false,
    this.tampered = false,
  });

  /// Ключ аккаунта, впервые увиденный (TOFU) или подтверждённый сверкой.
  Uint8List accountKey;
  int seenVersion;
  bool verified;

  /// Ключ аккаунта сменился после первого знакомства (переустановка без
  /// бэкапа или подмена сервером). Сбрасывается сверкой.
  bool keyChanged;

  /// Ключ не сошёлся с отпечатком из ссылки или с MAC подтверждения —
  /// сервер подменил ключи. Сбрасывается только сверкой эмодзи или QR.
  bool tampered;

  Map<String, dynamic> toJson() => {
    'ak': b64(accountKey),
    'seen': seenVersion,
    'verified': verified,
    'changed': keyChanged,
    'tampered': tampered,
  };

  factory PeerState.fromJson(Map<String, dynamic> j) => PeerState(
    accountKey: unb64(j['ak'] as String),
    seenVersion: j['seen'] as int,
    verified: j['verified'] as bool,
    keyChanged: j['changed'] as bool? ?? false,
    tampered: j['tampered'] as bool? ?? false,
  );
}

class E2EKeys {
  E2EKeys({
    required this.account,
    required this.device,
    Map<String, PairKey>? pairKeys,
    Map<String, PeerState>? peers,
    Set<String>? granted,
    Map<String, String>? inviteSecrets,
    this.listVersion = 0,
  }) : pairKeys = pairKeys ?? {},
       peers = peers ?? {},
       granted = granted ?? {},
       inviteSecrets = inviteSecrets ?? {};

  final KeyPair account;
  final DeviceKeys device;

  /// `group:epoch` → ключ.
  final Map<String, PairKey> pairKeys;

  /// uid партнёра → состояние.
  final Map<String, PeerState> peers;

  /// Кому этот ключ уже выдан: `group:epoch|device`.
  final Set<String> granted;

  /// Секреты приглашений по коду (§6.2), base64url.
  final Map<String, String> inviteSecrets;

  /// Версия своего опубликованного списка устройств.
  int listVersion;

  PairKey? keyFor(String keyId) => pairKeys[keyId];

  /// Ключ пары последней эпохи — им шифруется новое.
  PairKey? currentKey(String groupId) {
    PairKey? best;
    for (final k in pairKeys.values) {
      if (k.groupId == groupId && (best == null || k.epoch > best.epoch)) {
        best = k;
      }
    }
    return best;
  }

  static E2EKeys generate(E2ECrypto c, String deviceId) => E2EKeys(
    account: c.signKeyPair(),
    device: DeviceKeys.generate(c, deviceId),
  );
}

class E2EKeyStore {
  E2EKeyStore(this._c, this._vault, {this.slot = 'fork_e2e_keys_v1'});

  final E2ECrypto _c;
  final KeyVault _vault;

  /// Ключ записи в хранилище. Один на установку: аккаунт на устройстве один.
  final String slot;

  static Map<String, String> _pair(KeyPair k) => {
    'pk': b64(k.publicKey),
    'sk': b64(k.secretKey.extractBytes()),
  };

  KeyPair _unpair(Map<String, dynamic> j) => KeyPair(
    publicKey: unb64(j['pk'] as String),
    secretKey: _c.keyFromBytes(unb64(j['sk'] as String)),
  );

  Future<void> save(E2EKeys k) => _vault.write(
    slot,
    jsonEncode({
      'v': 1,
      'account': _pair(k.account),
      'device': {
        'id': k.device.id,
        'box': _pair(k.device.box),
        'sign': _pair(k.device.sign),
      },
      'pairs': [
        for (final p in k.pairKeys.values)
          {
            'group': p.groupId,
            'epoch': p.epoch,
            'key': b64(p.key.extractBytes()),
          },
      ],
      'peers': {for (final e in k.peers.entries) e.key: e.value.toJson()},
      'granted': k.granted.toList()..sort(),
      'invites': k.inviteSecrets,
      'list_version': k.listVersion,
    }),
  );

  /// null — ключей на устройстве нет (первый запуск или стёрты).
  Future<E2EKeys?> load() async {
    final raw = await _vault.read(slot);
    if (raw == null || raw.isEmpty) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['v'] != 1) throw FormatException('ключи: версия ${j['v']}');
    final d = (j['device'] as Map).cast<String, dynamic>();
    final pairs = <String, PairKey>{};
    for (final p in (j['pairs'] as List).cast<Map<String, dynamic>>()) {
      final k = PairKey(
        p['group'] as String,
        p['epoch'] as int,
        _c.keyFromBytes(unb64(p['key'] as String)),
      );
      pairs[k.keyId] = k;
    }
    return E2EKeys(
      account: _unpair((j['account'] as Map).cast<String, dynamic>()),
      device: DeviceKeys(
        id: d['id'] as String,
        box: _unpair((d['box'] as Map).cast<String, dynamic>()),
        sign: _unpair((d['sign'] as Map).cast<String, dynamic>()),
      ),
      pairKeys: pairs,
      peers: {
        for (final e in (j['peers'] as Map).cast<String, dynamic>().entries)
          e.key: PeerState.fromJson((e.value as Map).cast<String, dynamic>()),
      },
      granted: {...((j['granted'] as List?) ?? const []).cast<String>()},
      inviteSecrets: ((j['invites'] as Map?) ?? const {})
          .cast<String, String>(),
      listVersion: j['list_version'] as int? ?? 0,
    );
  }

  Future<void> wipe() => _vault.delete(slot);
}
