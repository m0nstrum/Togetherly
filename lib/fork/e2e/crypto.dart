/// Примитивы E2E поверх libsodium (docs/fork/E2E.md §3).
///
/// Своей криптографии нет: только вызовы libsodium и сборка байтов для них.
/// Всё, что подписывается или идёт в хэш, собирается [frame] — с длиной
/// каждого куска, чтобы разные наборы полей не давали одинаковые байты.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

export 'package:sodium/sodium_sumo.dart' show SecureKey, KeyPair, SodiumSumo;

/// Ошибка проверки: подпись, MAC, коммитмент или расшифровка не сошлись.
/// Её показывают человеку как «ключи не совпадают», а не как сбой.
class E2EVerifyError implements Exception {
  E2EVerifyError(this.message);
  final String message;
  @override
  String toString() => 'E2EVerifyError: $message';
}

class E2ECrypto {
  E2ECrypto(this.sodium);

  final SodiumSumo sodium;

  static Future<E2ECrypto> init() async =>
      E2ECrypto(await SodiumSumoInit.init());

  CryptoSumo get _c => sodium.crypto;

  // --- случайность и ключи ---

  Uint8List random(int n) => sodium.randombytes.buf(n);

  /// Ключ пары, ключ файла, ключ сессии комнаты — 32 случайных байта.
  SecureKey symmetricKey() => _c.aeadXChaCha20Poly1305IETF.keygen();

  SecureKey keyFromBytes(Uint8List b) => sodium.secureCopy(b);

  /// Ed25519: ключ аккаунта и подписи устройства.
  KeyPair signKeyPair() => _c.sign.keyPair();

  /// X25519: ключ устройства для доставки ключей пары.
  KeyPair boxKeyPair() => _c.box.keyPair();

  /// X25519 для обмена (сверка эмодзи, §6.3).
  KeyPair kxKeyPair() => _c.kx.keyPair();

  // --- симметричное шифрование записей (§8) ---

  int get aeadNonceBytes => _c.aeadXChaCha20Poly1305IETF.nonceBytes;

  Uint8List aeadEncrypt(
    Uint8List msg,
    Uint8List nonce,
    SecureKey key,
    Uint8List aad,
  ) => _c.aeadXChaCha20Poly1305IETF.encrypt(
    message: msg,
    nonce: nonce,
    key: key,
    additionalData: aad,
  );

  Uint8List aeadDecrypt(
    Uint8List ct,
    Uint8List nonce,
    SecureKey key,
    Uint8List aad,
  ) {
    try {
      return _c.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: ct,
        nonce: nonce,
        key: key,
        additionalData: aad,
      );
    } on SodiumException {
      throw E2EVerifyError('расшифровка не удалась');
    }
  }

  // --- доставка ключа устройству (sealed box) ---

  Uint8List seal(Uint8List msg, Uint8List boxPublicKey) =>
      _c.box.seal(message: msg, publicKey: boxPublicKey);

  Uint8List sealOpen(Uint8List ct, KeyPair box) {
    try {
      return _c.box.sealOpen(
        cipherText: ct,
        publicKey: box.publicKey,
        secretKey: box.secretKey,
      );
    } on SodiumException {
      throw E2EVerifyError('ключ адресован не этому устройству');
    }
  }

  // --- подписи ---

  Uint8List sign(Uint8List msg, SecureKey secretKey) =>
      _c.sign.detached(message: msg, secretKey: secretKey);

  bool verify(Uint8List msg, Uint8List sig, Uint8List publicKey) {
    if (sig.length != _c.sign.bytes ||
        publicKey.length != _c.sign.publicKeyBytes) {
      return false;
    }
    return _c.sign.verifyDetached(
      message: msg,
      signature: sig,
      publicKey: publicKey,
    );
  }

  // --- хэш и MAC ---

  Uint8List hash(Uint8List msg, {int outLen = 32, SecureKey? key}) =>
      _c.genericHash(message: msg, outLen: outLen, key: key);

  /// HMAC-SHA512-256 (crypto_auth): подтверждение приглашения (§6.2).
  Uint8List mac(Uint8List msg, SecureKey key) =>
      _c.auth(message: msg, key: key);

  bool macVerify(Uint8List msg, Uint8List tag, SecureKey key) {
    if (tag.length != _c.auth.bytes) return false;
    return _c.auth.verify(tag: tag, message: msg, key: key);
  }

  // --- обмен для сверки (crypto_kx) ---

  /// Общий секрет двух сторон: у инициатора `rx ‖ tx`, у ответчика `tx ‖ rx`
  /// — одни и те же 64 байта.
  Uint8List kxShared(
    KeyPair mine,
    Uint8List theirs, {
    required bool initiator,
  }) {
    final SessionKeys k;
    try {
      k = initiator
          ? _c.kx.clientSessionKeys(
              clientPublicKey: mine.publicKey,
              clientSecretKey: mine.secretKey,
              serverPublicKey: theirs,
            )
          : _c.kx.serverSessionKeys(
              serverPublicKey: mine.publicKey,
              serverSecretKey: mine.secretKey,
              clientPublicKey: theirs,
            );
    } on SodiumException {
      throw E2EVerifyError('плохой ключ обмена');
    }
    final a = initiator ? k.rx : k.tx;
    final b = initiator ? k.tx : k.rx;
    final out = Uint8List.fromList([...a.extractBytes(), ...b.extractBytes()]);
    k.rx.dispose();
    k.tx.dispose();
    return out;
  }

  // --- ключи из фразы или пароля (§7) ---

  int get pwhashSaltBytes => _c.pwhash.saltBytes;

  SecureKey pwhash(
    String secret,
    Uint8List salt, {
    required int opsLimit,
    required int memLimit,
  }) => _c.pwhash(
    outLen: 32,
    password: Int8List.fromList(utf8.encode(secret)),
    salt: salt,
    opsLimit: opsLimit,
    memLimit: memLimit,
  );

  int get pwhashOpsModerate => _c.pwhash.opsLimitModerate;

  /// Argon2id с 256 МиБ — секунды работы: в отдельном изоляте, чтобы не
  /// замирал интерфейс. Возвращает байты ключа.
  static Future<Uint8List> pwhashInIsolate(
    String secret,
    Uint8List salt, {
    required int opsLimit,
    required int memLimit,
  }) => Isolate.run(() async {
    final c = await E2ECrypto.init();
    final k = c.pwhash(secret, salt, opsLimit: opsLimit, memLimit: memLimit);
    try {
      return k.extractBytes();
    } finally {
      k.dispose();
    }
  });
}

/// Склейка кусков с длиной перед каждым (4 байта, big-endian).
Uint8List frame(Iterable<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    final len = ByteData(4)..setUint32(0, p.length);
    b
      ..add(len.buffer.asUint8List())
      ..add(p);
  }
  return b.toBytes();
}

Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// JSON с отсортированными ключами и без пробелов: одинаковые данные —
/// одинаковые байты на любом устройстве. Только для подписи и хэша.
String canonicalJson(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonicalJson).join(',')}]';
  return jsonEncode(v);
}

String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

Uint8List unb64(String s) => base64Url.decode(base64Url.normalize(s));

bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
