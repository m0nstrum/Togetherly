/// Шифрование полей записей PocketBase (PLAN S9, docs/fork/E2E.md §8).
///
/// Каждое чувствительное текстовое поле шифруется на месте: в колонке лежит
/// `e2e1.<key_id>.<nonce>.<ct>`. AAD привязывает шифртекст к коллекции, id
/// записи и полю — сервер не переложит его в чужое сообщение или поле.
/// Поле за полем, а не одним `enc` на запись: правка шлёт только изменённые
/// колонки (`chatUpdate`), и собирать для неё конверт целиком было бы не из
/// чего.
///
/// Значение без префикса — открытое, как писали до E2E (двойное чтение).
library;

import 'dart:convert';

import 'crypto.dart';
import 'envelope.dart';

/// Ключи пар, какие есть на устройстве.
abstract interface class E2EKeyring {
  PairKey? keyFor(String keyId);
  PairKey? currentKey(String groupId);
}

/// Как поле лежит в колонке: строка или JSON. Шифртекст в обоих случаях —
/// строка `e2e1.…`; JSON-колонка PocketBase строку принимает.
enum SealKind { text, json }

class SealedField {
  const SealedField.text({this.locked = ''}) : kind = SealKind.text;
  const SealedField.json({this.locked}) : kind = SealKind.json;

  final SealKind kind;

  /// Что лежит в поле, пока ключа нет.
  final Object? locked;
}

/// Какие поля каких коллекций шифруются. Числа, даты и флаги остаются
/// открытыми — по ним фильтрует и сортирует сервер.
const Map<String, Map<String, SealedField>> e2eFields = {
  'chat_messages': {
    'user_name': SealedField.text(),
    'text': SealedField.text(locked: e2eLockedText),
    'pin_title': SealedField.text(),
    'reply_to_name': SealedField.text(),
    'reply_to_text': SealedField.text(),
    'reactions': SealedField.json(locked: <String, dynamic>{}),
  },
};

const String e2eFieldPrefix = 'e2e1.';

/// Поле, которое не открылось (ключа ещё нет): шифртекст здесь, в колонке —
/// заглушка. Когда ключ придёт, [RecordCodec.retry] вернёт текст на место.
const String e2eLockedKey = 'e2e_locked';

/// Что видно вместо текста, пока ключа нет.
const String e2eLockedText = '🔒';

bool isSealedValue(Object? v) => v is String && v.startsWith(e2eFieldPrefix);

class RecordCodec {
  RecordCodec(E2ECrypto c, this.keys) : _c = c;

  /// Без libsodium и ключей: шифрованные поля только прячутся за заглушку.
  RecordCodec.locked() : _c = null, keys = const _NoKeys();

  final E2ECrypto? _c;
  final E2EKeyring keys;

  static bool covers(String collection) => e2eFields.containsKey(collection);

  String sealField(
    String collection,
    String recordId,
    String field,
    String plain,
    PairKey key,
  ) {
    final c = _c!;
    final nonce = c.random(c.aeadNonceBytes);
    final ct = c.aeadEncrypt(
      utf8Bytes(plain),
      nonce,
      key.key,
      Envelope.aad(
        envelopeVersion,
        key.keyId,
        RecordPlace(collection, recordId, field),
      ),
    );
    return '$e2eFieldPrefix${key.keyId}.${b64(nonce)}.${b64(ct)}';
  }

  /// Открытый текст поля; null — ключа нет или шифртекст не сходится.
  String? openField(
    String collection,
    String recordId,
    String field,
    String sealed,
  ) {
    final parts = sealed.substring(e2eFieldPrefix.length).split('.');
    if (parts.length != 3) return null;
    final key = keys.keyFor(parts[0]);
    final c = _c;
    if (key == null || c == null) return null;
    try {
      final plain = c.aeadDecrypt(
        unb64(parts[2]),
        unb64(parts[1]),
        key.key,
        Envelope.aad(
          envelopeVersion,
          key.keyId,
          RecordPlace(collection, recordId, field),
        ),
      );
      return utf8.decode(plain);
    } on Object {
      return null;
    }
  }

  /// Что шифровать: null — поле пустое или уже шифр.
  static String? _plain(SealKind kind, Object? v) {
    if (v == null || isSealedValue(v)) return null;
    switch (kind) {
      case SealKind.text:
        return v is String && v.isNotEmpty ? v : null;
      case SealKind.json:
        if ((v is Map && v.isEmpty) || (v is List && v.isEmpty)) return null;
        return jsonEncode(v);
    }
  }

  /// Шифрует поля тела запроса записи [recordId] пары [groupId]. Нет ключа
  /// пары — тело как есть (пара ещё не обменялась ключами).
  Map<String, dynamic> encode(
    String collection,
    String recordId,
    String groupId,
    Map<String, dynamic> body,
  ) {
    final fields = e2eFields[collection];
    final key = _c == null ? null : keys.currentKey(groupId);
    if (fields == null || key == null || recordId.isEmpty) return body;
    final out = Map<String, dynamic>.of(body);
    for (final e in fields.entries) {
      final plain = _plain(e.value.kind, out[e.key]);
      if (plain == null) continue;
      out[e.key] = sealField(collection, recordId, e.key, plain, key);
    }
    out.remove(e2eLockedKey);
    return out;
  }

  /// Расшифровывает поля записи с сервера. Не открылось — в поле заглушка,
  /// шифртекст уходит в [e2eLockedKey].
  Map<String, dynamic> decode(String collection, Map<String, dynamic> rec) {
    final fields = e2eFields[collection];
    final id = rec['id'];
    if (fields == null || id is! String) return rec;
    Map<String, dynamic>? out;
    Map<String, dynamic>? locked;
    for (final e in fields.entries) {
      final f = e.key;
      final v = rec[f];
      if (!isSealedValue(v)) continue;
      out ??= Map<String, dynamic>.of(rec);
      final plain = openField(collection, id, f, v as String);
      Object? value;
      var ok = plain != null;
      if (ok && e.value.kind == SealKind.json) {
        try {
          value = jsonDecode(plain);
        } on FormatException {
          ok = false;
        }
      } else {
        value = plain;
      }
      if (ok) {
        out[f] = value;
      } else {
        out[f] = e.value.locked;
        (locked ??= {})[f] = v;
      }
    }
    if (out == null) return rec;
    if (locked != null) {
      out[e2eLockedKey] = locked;
    } else {
      out.remove(e2eLockedKey);
    }
    return out;
  }

  /// Запись из кэша с неоткрытыми полями: пробуем снова. null — открыть
  /// нечего или по-прежнему нечем.
  Map<String, dynamic>? retry(String collection, Map<String, dynamic> rec) {
    final locked = rec[e2eLockedKey];
    if (locked is! Map) return null;
    final restored = decode(collection, {
      ...rec,
      for (final e in locked.entries) e.key.toString(): e.value,
    });
    final still = restored[e2eLockedKey];
    if (still is Map && still.length == locked.length) return null;
    return restored;
  }

  /// Тело ответа PocketBase: одна запись или страница `{items: [...]}`.
  Object? decodeResponse(String collection, Object? json) {
    if (json is! Map<String, dynamic>) return json;
    final items = json['items'];
    if (items is List) {
      return {
        ...json,
        'items': [
          for (final r in items)
            r is Map<String, dynamic> ? decode(collection, r) : r,
        ],
      };
    }
    return decode(collection, json);
  }
}

class _NoKeys implements E2EKeyring {
  const _NoKeys();
  @override
  PairKey? keyFor(String keyId) => null;
  @override
  PairKey? currentKey(String groupId) => null;
}
