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

  /// Пара ровно из [members] с ключом; null — такой нет.
  String? groupWith(Set<String> members);
}

/// Как поле лежит в колонке: строка или JSON. Шифртекст в обоих случаях —
/// строка `e2e1.…`; JSON-колонка PocketBase строку принимает. Поля других
/// типов (даты) переезжают в общее поле [e2eMovedField], а колонка пустеет.
enum SealKind { text, json, jsonPartial, moved }

/// Поле записи, куда переезжают поля, которые на месте не зашифровать.
const String e2eMovedField = 'enc';

/// Ключ шифра внутри частично шифрованного JSON.
const String e2ePartialKey = 'e2e';

/// Ключи `memories.data`, которые читает или пишет сервер: капсула
/// (server/internal/domain/capsule `visible`, `sealed`/`openAt`), счётчик
/// комментариев (comments_count.js), наклейки (правка на сервере).
const Set<String> memoryOpenKeys = {
  'id',
  'groupId',
  'type',
  'authorUid',
  'authorName',
  'authorAvatar',
  'createdAt',
  'editedAt',
  'addedAt',
  'tz',
  'sealed',
  'openAt',
  'isPinned',
  'savedBy',
  'reactions',
  'commentsCount',
  'dailyTaskId',
  'capsuleOpened',
  'stickers',
  'deleted',
};

class SealedField {
  const SealedField.text({this.locked = ''})
    : kind = SealKind.text,
      cleared = '',
      open = const {};
  const SealedField.json({this.locked})
    : kind = SealKind.json,
      cleared = null,
      open = const {};

  /// JSON-объект, где ключи [open] остаются открытыми (их читает сервер),
  /// а остальное уходит шифром в ключ [e2ePartialKey].
  const SealedField.jsonPartial(this.open)
    : kind = SealKind.jsonPartial,
      locked = null,
      cleared = null;

  /// Переезжает в [e2eMovedField], в колонке остаётся [cleared]. Правка
  /// записи шлёт все такие поля разом (иначе пропущенные сотрутся из `enc`).
  const SealedField.moved({this.locked = '', this.cleared = ''})
    : kind = SealKind.moved,
      open = const {};

  final SealKind kind;

  /// Что остаётся в колонке переехавшего поля: одно значение на все записи.
  final Object? cleared;

  /// Открытые ключи частично шифрованного JSON.
  final Set<String> open;

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
  'live_location': {'data': SealedField.json()},
  'memories': {'data': SealedField.jsonPartial(memoryOpenKeys)},
  'memory_comments': {'text': SealedField.text(locked: e2eLockedText)},
  'cycle_entries': {
    'kind': SealedField.text(),
    'flow': SealedField.text(),
    // По датам отметок цикл читается и без `kind`. Колонка обязательная —
    // в ней одна и та же дата у всех. Без ключа отметка уезжает туда же, а
    // не в «сегодня» (`CycleEntry.fromPb` так читает пустую дату).
    'day': SealedField.moved(cleared: e2eClearedDate, locked: e2eClearedDate),
  },
};

const String e2eFieldPrefix = 'e2e1.';

/// Дата в обязательной колонке, чьё значение переехало в `enc`.
const String e2eClearedDate = '2000-01-01 00:00:00.000Z';

/// Поле, которое не открылось (ключа ещё нет): шифртекст здесь, в колонке —
/// заглушка. Когда ключ придёт, [RecordCodec.retry] вернёт текст на место.
const String e2eLockedKey = 'e2e_locked';

/// Что видно вместо текста, пока ключа нет.
const String e2eLockedText = '🔒';

bool isSealedValue(Object? v) => v is String && v.startsWith(e2eFieldPrefix);

/// Участники канала геопозиции `pair_<a>_<b>`; null — канал не такой.
Set<String>? pairChannelMembers(Object? channel) {
  if (channel is! String || !channel.startsWith('pair_')) return null;
  final parts = channel.substring(5).split('_');
  if (parts.length != 2 || parts.any((p) => p.isEmpty)) return null;
  return parts.toSet();
}

/// Фильтр PocketBase: в записи коллекции есть поле, сохранённое открыто.
/// Строка — без префикса; JSON — непустой объект (`":` внутри, у шифртекста
/// его нет); переехавшее поле — колонка не пустая и не [SealedField.cleared].
String plaintextFilter(String collection) => e2eFields[collection]!.entries
    .map(
      (e) => switch (e.value.kind) {
        SealKind.text => "(${e.key} != '' && ${e.key} !~ '$e2eFieldPrefix')",
        SealKind.json => "${e.key} ~ '\":'",
        SealKind.jsonPartial =>
          "(${e.key} ~ '\":' && ${e.key} !~ '$e2eFieldPrefix')",
        SealKind.moved =>
          "(${e.key} != '' && ${e.key} != '${e.value.cleared}')",
      },
    )
    .join(' || ');

class RecordCodec {
  RecordCodec(E2ECrypto c, this.keys) : _c = c;

  /// Без libsodium и ключей: шифрованные поля только прячутся за заглушку.
  RecordCodec.locked() : _c = null, keys = const _NoKeys();

  final E2ECrypto? _c;
  final E2EKeyring keys;

  /// null — libsodium не загрузилась.
  E2ECrypto? get crypto => _c;

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
      case SealKind.moved:
      case SealKind.jsonPartial:
        return null;
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
    final moved = <String, dynamic>{};
    for (final e in fields.entries) {
      if (e.value.kind == SealKind.moved) {
        final v = out[e.key];
        if (v != null &&
            v != e.value.cleared &&
            !isSealedValue(out[e2eMovedField])) {
          moved[e.key] = v;
          out[e.key] = e.value.cleared;
        }
        continue;
      }
      if (e.value.kind == SealKind.jsonPartial) {
        final v = out[e.key];
        if (v is! Map || v[e2ePartialKey] != null) continue;
        final rest = <String, dynamic>{};
        final kept = <String, dynamic>{};
        for (final kv in v.entries) {
          final k = kv.key.toString();
          (e.value.open.contains(k) ? kept : rest)[k] = kv.value;
        }
        if (rest.isEmpty) continue;
        kept[e2ePartialKey] = sealField(
          collection,
          recordId,
          e.key,
          jsonEncode(rest),
          key,
        );
        out[e.key] = kept;
        continue;
      }
      final plain = _plain(e.value.kind, out[e.key]);
      if (plain == null) continue;
      out[e.key] = sealField(collection, recordId, e.key, plain, key);
    }
    if (moved.isNotEmpty) {
      out[e2eMovedField] = sealField(
        collection,
        recordId,
        e2eMovedField,
        jsonEncode(moved),
        key,
      );
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
    final enc = rec[e2eMovedField];
    if (isSealedValue(enc) &&
        fields.values.any((f) => f.kind == SealKind.moved)) {
      out = Map<String, dynamic>.of(rec);
      final plain = openField(collection, id, e2eMovedField, enc as String);
      Map<String, dynamic>? moved;
      try {
        if (plain != null) moved = jsonDecode(plain) as Map<String, dynamic>;
      } on Object {
        moved = null;
      }
      for (final e in fields.entries) {
        if (e.value.kind != SealKind.moved) continue;
        out[e.key] = moved != null && moved.containsKey(e.key)
            ? moved[e.key]
            : e.value.locked;
      }
      out.remove(e2eMovedField);
      if (moved == null) (locked ??= {})[e2eMovedField] = enc;
    }
    for (final e in fields.entries) {
      if (e.value.kind != SealKind.jsonPartial) continue;
      final v = rec[e.key];
      if (v is! Map || !isSealedValue(v[e2ePartialKey])) continue;
      out ??= Map<String, dynamic>.of(rec);
      final sealed = v[e2ePartialKey] as String;
      final kept = <String, dynamic>{
        for (final kv in v.entries)
          if (kv.key != e2ePartialKey) kv.key.toString(): kv.value,
      };
      final plain = openField(collection, id, e.key, sealed);
      Map<String, dynamic>? rest;
      try {
        if (plain != null) rest = jsonDecode(plain) as Map<String, dynamic>;
      } on Object {
        rest = null;
      }
      if (rest != null) {
        out[e.key] = {...rest, ...kept};
      } else {
        out[e.key] = kept;
        (locked ??= {})[e.key] = v;
      }
    }
    for (final e in fields.entries) {
      final f = e.key;
      final v = rec[f];
      if (e.value.kind == SealKind.moved ||
          e.value.kind == SealKind.jsonPartial ||
          !isSealedValue(v)) {
        continue;
      }
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

  /// Эфемерное сообщение канала Centrifugo: [payload] целиком в шифр, AAD —
  /// канал, тип и время (§8).
  String sealChannel(
    ChannelPlace place,
    Map<String, dynamic> payload,
    PairKey key,
  ) {
    final c = _c!;
    final nonce = c.random(c.aeadNonceBytes);
    final ct = c.aeadEncrypt(
      utf8Bytes(jsonEncode(payload)),
      nonce,
      key.key,
      Envelope.aad(envelopeVersion, key.keyId, place),
    );
    return '$e2eFieldPrefix${key.keyId}.${b64(nonce)}.${b64(ct)}';
  }

  /// null — нечем открыть или подделка.
  Map<String, dynamic>? openChannel(ChannelPlace place, String sealed) {
    if (!isSealedValue(sealed)) return null;
    final parts = sealed.substring(e2eFieldPrefix.length).split('.');
    final c = _c;
    if (parts.length != 3 || c == null) return null;
    final key = keys.keyFor(parts[0]);
    if (key == null) return null;
    try {
      final plain = c.aeadDecrypt(
        unb64(parts[2]),
        unb64(parts[1]),
        key.key,
        Envelope.aad(envelopeVersion, key.keyId, place),
      );
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on Object {
      return null;
    }
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
  @override
  String? groupWith(Set<String> members) => null;
}
