/// Привязка нового устройства к аккаунту по QR (docs/E2E.md §5.3, BACKLOG
/// T3).
///
/// 1. Новое устройство заводит свои ключи устройства и одноразовый секрет S.
///    На сервер (`e2e_links`) уходят публичные ключи и MAC от S; сам S —
///    только в QR на экране.
/// 2. Старое устройство сканирует QR, проверяет MAC (сервер не подменит
///    ключи устройства), спрашивает человека и кладёт в `payload` ключ
///    аккаунта, ключи пар, ключ бэкапа и сверенных партнёров: sealed box на
///    ключ нового устройства и поверх — AEAD ключом из S (сервер не
///    подсунет свой пакет).
/// 3. Новое устройство открывает пакет, сверяет ключ аккаунта с
///    опубликованным и добавляет себя в подписанный список устройств.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'backup.dart';
import 'crypto.dart';
import 'devices.dart';
import 'envelope.dart';
import 'key_store.dart';

const _qrPrefix = 'tethered-link:1:';
final _idShape = RegExp(r'^[a-z0-9]{15}$');

/// uid — id записи PocketBase; в QR — только безопасные символы, без «:».
final _uidShape = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Что зашито в QR нового устройства.
class LinkQr {
  LinkQr({required this.uid, required this.linkId, required this.secret});

  final String uid;
  final String linkId;
  final Uint8List secret;

  String encode() =>
      '$_qrPrefix$uid:$linkId:${base64Url.encode(secret).replaceAll('=', '')}';

  /// null — это не QR привязки или он испорчен.
  static LinkQr? parse(String raw) {
    final s = raw.trim();
    if (!s.startsWith(_qrPrefix)) return null;
    final parts = s.substring(_qrPrefix.length).split(':');
    if (parts.length != 3) return null;
    final uid = parts[0], link = parts[1];
    if (!_uidShape.hasMatch(uid) || !_idShape.hasMatch(link)) return null;
    try {
      final secret = base64Url.decode(base64Url.normalize(parts[2]));
      if (secret.length != 32) return null;
      return LinkQr(uid: uid, linkId: link, secret: Uint8List.fromList(secret));
    } on FormatException {
      return null;
    }
  }
}

/// Запись `e2e_links` в том виде, в каком её отдаёт сервер.
class LinkRecord {
  LinkRecord({
    required this.id,
    required this.uid,
    required this.device,
    required this.mac,
    this.payload = '',
  });

  final String id;
  final String uid;
  final DeviceEntry device;
  final Uint8List mac;
  final String payload;
}

/// Что старое устройство отдаёт новому.
class LinkBundle {
  LinkBundle({
    required this.accountSecret,
    required this.pairKeys,
    this.backup,
    this.peers = const {},
  });

  /// Секрет Ed25519 ключа аккаунта (64 байта libsodium).
  final Uint8List accountSecret;
  final List<PairKey> pairKeys;
  final BackupKey? backup;
  final Map<String, PeerState> peers;
}

Uint8List _macInput(String uid, String linkId, DeviceEntry d) =>
    utf8Bytes('tethered-link-v1|$uid|$linkId|${canonicalJson(d.toJson())}');

Uint8List _aad(String uid, String linkId) =>
    utf8Bytes('tethered-link-payload-v1|$uid|$linkId');

/// Ключ AEAD пакета — из секрета QR.
SecureKey _payloadKey(E2ECrypto c, Uint8List secret) => c.keyFromBytes(
  c.hash(utf8Bytes('tethered-link-payload'), key: c.keyFromBytes(secret)),
);

/// Предложение нового устройства: его ключи, секрет и QR.
class LinkOffer {
  LinkOffer._(this.qr, this.device);

  final LinkQr qr;
  final DeviceKeys device;

  static LinkOffer create(E2ECrypto c, String uid, {String? linkId}) {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final id =
        linkId ??
        String.fromCharCodes(
          c.random(15).map((b) => abc.codeUnitAt(b % abc.length)),
        );
    return LinkOffer._(
      LinkQr(uid: uid, linkId: id, secret: c.random(32)),
      DeviceKeys.generate(c, b64(c.random(9))),
    );
  }

  /// Тело записи `e2e_links`.
  Map<String, dynamic> record(E2ECrypto c) {
    final entry = device.entry();
    return {
      'id': qr.linkId,
      'user_uid': qr.uid,
      'device': entry.toJson(),
      'mac': b64(
        c.mac(_macInput(qr.uid, qr.linkId, entry), c.keyFromBytes(qr.secret)),
      ),
    };
  }

  /// Открыть пакет старого устройства. Чужой или испорченный —
  /// [E2EVerifyError].
  LinkBundle open(E2ECrypto c, String payload) {
    final Map<String, dynamic> outer;
    try {
      outer = (jsonDecode(payload) as Map).cast<String, dynamic>();
    } catch (_) {
      throw E2EVerifyError('пакет привязки не разбирается');
    }
    if (outer['v'] != 1) throw E2EVerifyError('пакет привязки: версия');
    final inner = c.aeadDecrypt(
      unb64(outer['ct'] as String),
      unb64(outer['nonce'] as String),
      _payloadKey(c, qr.secret),
      _aad(qr.uid, qr.linkId),
    );
    final j = (jsonDecode(utf8.decode(c.sealOpen(inner, device.box))) as Map)
        .cast<String, dynamic>();
    if (j['user'] != qr.uid ||
        j['link'] != qr.linkId ||
        j['device'] != device.id) {
      throw E2EVerifyError('пакет привязки адресован не сюда');
    }
    return LinkBundle(
      accountSecret: unb64(j['account'] as String),
      pairKeys: [
        for (final p in (j['pairs'] as List).cast<Map>())
          PairKey(
            p['group'] as String,
            p['epoch'] as int,
            c.keyFromBytes(unb64(p['key'] as String)),
          ),
      ],
      backup: j['backup'] == null
          ? null
          : BackupKey.fromJson(c, (j['backup'] as Map).cast<String, dynamic>()),
      peers: {
        for (final e in ((j['peers'] as Map?) ?? const {}).entries)
          e.key as String: PeerState.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          ),
      },
    );
  }
}

/// Старое устройство: проверить запись по QR и запечатать пакет.
/// Запись не от этого QR (подмена сервером) — [E2EVerifyError].
String sealLinkBundle(
  E2ECrypto c, {
  required LinkQr qr,
  required LinkRecord record,
  required LinkBundle bundle,
}) {
  if (record.id != qr.linkId || record.uid != qr.uid) {
    throw E2EVerifyError('запись привязки не от этого QR');
  }
  if (record.device.kind != DeviceKind.full ||
      !c.macVerify(
        _macInput(qr.uid, qr.linkId, record.device),
        record.mac,
        c.keyFromBytes(qr.secret),
      )) {
    throw E2EVerifyError('ключи нового устройства не сходятся с QR');
  }
  final plain = utf8Bytes(
    jsonEncode({
      'user': qr.uid,
      'link': qr.linkId,
      'device': record.device.id,
      'account': b64(bundle.accountSecret),
      'pairs': [
        for (final k in bundle.pairKeys)
          {
            'group': k.groupId,
            'epoch': k.epoch,
            'key': b64(k.key.extractBytes()),
          },
      ],
      if (bundle.backup != null) 'backup': bundle.backup!.toJson(),
      'peers': {for (final e in bundle.peers.entries) e.key: e.value.toJson()},
    }),
  );
  final inner = c.seal(plain, record.device.boxKey);
  final nonce = c.random(c.aeadNonceBytes);
  return jsonEncode({
    'v': 1,
    'nonce': b64(nonce),
    'ct': b64(
      c.aeadEncrypt(
        inner,
        nonce,
        _payloadKey(c, qr.secret),
        _aad(qr.uid, qr.linkId),
      ),
    ),
  });
}
