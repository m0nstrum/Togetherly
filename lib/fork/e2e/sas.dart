/// Сверка ключей эмодзи (docs/E2E.md §6.3, схема Matrix SAS).
///
/// Порядок сообщений: инициатор шлёт коммитмент своего эфемерного ключа,
/// ответчик — свой эфемерный ключ, инициатор раскрывает свой. К моменту,
/// когда сервер-посредник видит ключ инициатора, свой ключ ответчику он уже
/// выбрал, — подобрать совпадение перебором нельзя, остаётся одна попытка с
/// шансом 2⁻⁴².
library;

import 'dart:typed_data';

import 'crypto.dart';
import 'sas_emoji.dart';

const int sasEmojiCount = 7;

/// Результат сверки: 7 индексов в [sasEmoji]. Совпали у обоих — ключи
/// аккаунтов настоящие.
class SasCode {
  SasCode(this.indices) : assert(indices.length == sasEmojiCount);

  final List<int> indices;

  List<SasEmoji> get emoji => [for (final i in indices) sasEmoji[i]];

  @override
  bool operator ==(Object other) =>
      other is SasCode &&
      other.indices.length == indices.length &&
      bytesEqual(other.indices, indices);

  @override
  int get hashCode => Object.hashAll(indices);

  @override
  String toString() => emoji.map((e) => e.symbol).join(' ');

  /// Первые 42 бита — 7 групп по 6 бит, старшие биты первыми.
  static SasCode fromBytes(Uint8List b) {
    var acc = BigInt.zero;
    for (var i = 0; i < 6; i++) {
      acc = (acc << 8) | BigInt.from(b[i]);
    }
    return SasCode([
      for (var i = 0; i < sasEmojiCount; i++)
        ((acc >> (48 - 6 * (i + 1))) & BigInt.from(63)).toInt(),
    ]);
  }
}

Uint8List _commitment(
  E2ECrypto c,
  Uint8List ephemeral,
  Uint8List akInitiator,
  Uint8List akResponder,
) => c.hash(
  frame([
    utf8Bytes('tethered-sas-commit-v1'),
    ephemeral,
    akInitiator,
    akResponder,
  ]),
);

SasCode _code(
  E2ECrypto c,
  Uint8List shared,
  Uint8List akInitiator,
  Uint8List akResponder,
  Uint8List eInitiator,
  Uint8List eResponder,
) {
  final key = c.keyFromBytes(shared);
  try {
    final h = c.hash(
      frame([
        utf8Bytes('tethered-sas-v1'),
        akInitiator,
        akResponder,
        eInitiator,
        eResponder,
      ]),
      outLen: 16,
      key: key,
    );
    return SasCode.fromBytes(h);
  } finally {
    key.dispose();
  }
}

/// Сторона, начавшая сверку. [myAccount] и [theirAccount] — публичные ключи
/// аккаунтов в том виде, в каком их видит это устройство.
class SasInitiator {
  SasInitiator(this._c, {required this.myAccount, required this.theirAccount})
    : _e = _c.kxKeyPair();

  final E2ECrypto _c;
  final Uint8List myAccount;
  final Uint8List theirAccount;
  final KeyPair _e;

  /// Шаг 1: коммитмент — уходит партнёру.
  Uint8List get commitment =>
      _commitment(_c, _e.publicKey, myAccount, theirAccount);

  /// Шаг 3: получив ключ ответчика, раскрыть свой и посчитать эмодзи.
  (Uint8List reveal, SasCode code) onAccept(Uint8List responderEphemeral) {
    final shared = _c.kxShared(_e, responderEphemeral, initiator: true);
    final code = _code(
      _c,
      shared,
      myAccount,
      theirAccount,
      _e.publicKey,
      responderEphemeral,
    );
    return (_e.publicKey, code);
  }

  void dispose() => _e.secretKey.dispose();
}

class SasResponder {
  SasResponder(
    this._c, {
    required this.myAccount,
    required this.theirAccount,
    required Uint8List commitment,
  }) : _commit = commitment,
       _e = _c.kxKeyPair();

  final E2ECrypto _c;
  final Uint8List myAccount;
  final Uint8List theirAccount;
  final Uint8List _commit;
  final KeyPair _e;

  /// Шаг 2: свой эфемерный ключ — уходит инициатору.
  Uint8List get ephemeral => _e.publicKey;

  /// Шаг 4: проверить раскрытый ключ по коммитменту и посчитать эмодзи.
  SasCode onReveal(Uint8List initiatorEphemeral) {
    if (!bytesEqual(
      _commitment(_c, initiatorEphemeral, theirAccount, myAccount),
      _commit,
    )) {
      throw E2EVerifyError('ключ сверки не совпал с обещанным');
    }
    final shared = _c.kxShared(_e, initiatorEphemeral, initiator: false);
    return _code(
      _c,
      shared,
      theirAccount,
      myAccount,
      initiatorEphemeral,
      _e.publicKey,
    );
  }

  void dispose() => _e.secretKey.dispose();
}
