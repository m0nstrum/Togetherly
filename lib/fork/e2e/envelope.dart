/// Конверт шифртекста (docs/E2E.md §8).
///
/// Лежит в поле `enc` записи как JSON. AAD привязывает шифртекст к месту:
/// сервер не может переложить его в другую запись, поле или пару.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'crypto.dart';

const int envelopeVersion = 1;
const String envelopeAlg = 'xchacha20poly1305-ietf';

/// Ключ пары эпохи [epoch]. `key_id` конверта — `group:epoch`.
class PairKey {
  PairKey(this.groupId, this.epoch, this.key);

  final String groupId;
  final int epoch;
  final SecureKey key;

  String get keyId => '$groupId:$epoch';
}

/// Где лежит шифртекст: от этого зависит AAD.
sealed class EnvelopePlace {
  const EnvelopePlace();
  List<String> get parts;
}

/// Поле записи PocketBase.
class RecordPlace extends EnvelopePlace {
  const RecordPlace(this.collection, this.recordId, this.field);
  final String collection;
  final String recordId;
  final String field;
  @override
  List<String> get parts => ['record', collection, recordId, field];
}

/// Эфемерное сообщение Centrifugo (`typing`, штрихи, точки).
class ChannelPlace extends EnvelopePlace {
  const ChannelPlace(this.channel, this.type, this.time);
  final String channel;
  final String type;
  final int time;
  @override
  List<String> get parts => ['channel', channel, type, '$time'];
}

class Envelope {
  Envelope({
    required this.keyId,
    required this.nonce,
    required this.ct,
    this.v = envelopeVersion,
  });

  final int v;
  final String keyId;
  final Uint8List nonce;
  final Uint8List ct;

  Map<String, dynamic> toJson() => {
    'enc_v': v,
    'alg': envelopeAlg,
    'key_id': keyId,
    'nonce': b64(nonce),
    'ct': b64(ct),
  };

  factory Envelope.fromJson(Map<String, dynamic> j) {
    final v = j['enc_v'];
    if (v is! int || v > envelopeVersion || v < 1) {
      throw FormatException('конверт: неизвестная версия $v');
    }
    if (j['alg'] != envelopeAlg) {
      throw FormatException('конверт: алгоритм ${j['alg']}');
    }
    return Envelope(
      v: v,
      keyId: j['key_id'] as String,
      nonce: unb64(j['nonce'] as String),
      ct: unb64(j['ct'] as String),
    );
  }

  static Uint8List aad(int v, String keyId, EnvelopePlace place) => frame([
    utf8Bytes('tethered-enc'),
    utf8Bytes('$v'),
    ...place.parts.map(utf8Bytes),
    utf8Bytes(keyId),
  ]);
}

class EnvelopeCipher {
  EnvelopeCipher(this._c);

  final E2ECrypto _c;

  /// Шифрует [plain] (JSON полей, что раньше лежали открыто).
  Envelope seal(Map<String, dynamic> plain, PairKey key, EnvelopePlace place) {
    final nonce = _c.random(_c.aeadNonceBytes);
    final ct = _c.aeadEncrypt(
      utf8Bytes(jsonEncode(plain)),
      nonce,
      key.key,
      Envelope.aad(envelopeVersion, key.keyId, place),
    );
    return Envelope(keyId: key.keyId, nonce: nonce, ct: ct);
  }

  /// Расшифровывает; [keyFor] находит ключ по `key_id` (эпохи пары).
  Map<String, dynamic> open(
    Envelope e,
    PairKey? Function(String keyId) keyFor,
    EnvelopePlace place,
  ) {
    final key = keyFor(e.keyId);
    if (key == null) throw E2EVerifyError('нет ключа ${e.keyId}');
    final plain = _c.aeadDecrypt(
      e.ct,
      e.nonce,
      key.key,
      Envelope.aad(e.v, e.keyId, place),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}
