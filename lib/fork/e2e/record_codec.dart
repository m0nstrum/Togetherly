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
enum SealKind { text, json, jsonPartial, mapValues, moved }

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
  'createdAt',
  'editedAt',
  'addedAt',
  'tz',
  'sealed',
  'openAt',
  'isPinned',
  'savedBy',
  'commentsCount',
  'capsuleOpened',
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

  /// Словарь «участник → значение», где каждое значение — отдельный шифр
  /// (AAD — поле и ключ): сервер правит словарь по одному участнику
  /// (`/api/group/patch-map`) и всё остальное не трогает.
  const SealedField.mapValues()
    : kind = SealKind.mapValues,
      locked = null,
      cleared = null,
      open = const {};

  /// JSON-объект, где ключи [open] остаются открытыми (их читает сервер),
  /// а остальное уходит шифром в ключ [e2ePartialKey].
  const SealedField.jsonPartial(this.open)
    : kind = SealKind.jsonPartial,
      locked = null,
      cleared = null;

  /// Переезжает в [e2eMovedField], в колонке остаётся [cleared]. Поля, которых
  /// нет в правке, `encode` добирает из контекста записи.
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
    'pin_thumb': SealedField.text(),
    'reply_to_name': SealedField.text(),
    'reply_to_text': SealedField.text(),
    'reactions': SealedField.json(locked: <String, dynamic>{}),
    // Ссылки на файлы (сами файлы — шифром), облик кружка и голосового.
    'voice_url': SealedField.text(),
    'voice_peaks': SealedField.text(),
    'note_url': SealedField.text(),
    'note_thumb': SealedField.text(),
    'note_shape': SealedField.text(),
    'note_hearts': SealedField.text(),
    'face': SealedField.text(),
    // Числа — в `enc`: цвета, положение лица, длительности.
    'color': SealedField.moved(cleared: 0, locked: 0),
    'text_color': SealedField.moved(cleared: 0, locked: 0),
    'face_x': SealedField.moved(cleared: 0, locked: 0),
    'face_y': SealedField.moved(cleared: 0, locked: 0),
    'call_ms': SealedField.moved(cleared: 0, locked: 0),
    'voice_ms': SealedField.moved(cleared: 0, locked: 0),
    'note_ms': SealedField.moved(cleared: 0, locked: 0),
  },
  'live_location': {'data': SealedField.json()},
  'memories': {
    'data': SealedField.jsonPartial(memoryOpenKeys),
    'author_name': SealedField.text(),
    'author_avatar': SealedField.text(),
  },
  'memory_comments': {
    'text': SealedField.text(locked: e2eLockedText),
    'author_name': SealedField.text(),
    'author_avatar': SealedField.text(),
  },
  'wishes': {
    'title': SealedField.text(),
    'note': SealedField.text(),
    'done_note': SealedField.text(),
    'url': SealedField.text(),
    'image': SealedField.text(),
    'shop': SealedField.text(),
    'symbol': SealedField.text(),
    'kind': SealedField.text(),
    'category': SealedField.text(),
    'currency': SealedField.text(),
    'price': SealedField.moved(cleared: 0, locked: 0),
    'done_at': SealedField.moved(),
  },
  'wish_categories': {
    'title': SealedField.text(),
    'note': SealedField.text(),
    'symbol': SealedField.text(),
  },
  'canvas_catalogue': {'name': SealedField.text()},
  'canvas_meta': {
    'coloring_id': SealedField.text(),
    'coloring_mode': SealedField.text(),
    'coloring_outline': SealedField.text(),
    'coloring_done': SealedField.json(),
    'bg_color': SealedField.moved(cleared: 0, locked: 0),
  },
  'mascots': {'name': SealedField.text(), 'image_url': SealedField.text()},
  // Свой профиль — личным ключом (видят только свои устройства). Партнёру
  // тот же профиль уходит карточкой в записи пары (`groups.member_cards`).
  'users': {
    'name': SealedField.text(),
    'display_name': SealedField.text(),
    'avatar_url': SealedField.text(),
    'banner_url': SealedField.text(),
    'gender': SealedField.text(),
    'birth_date': SealedField.text(),
    'solo_timers': SealedField.json(),
    'mascot_sleep': SealedField.json(),
    'custom_themes': SealedField.json(),
    'miss_you_wishes': SealedField.json(),
  },
  // «Смотрим вместе»: история и свои ролики (файлы — шифром, как media).
  'watch_history': {
    'url': SealedField.text(),
    'title': SealedField.text(),
    'thumb': SealedField.text(),
    'kind': SealedField.text(),
  },
  'watch_videos': {'title': SealedField.text()},
  // Пишет сервер (gifts.pb.js, chest.pb.js) — шифр от клиента как есть.
  'gifts': {
    'note': SealedField.text(),
    'reply': SealedField.text(),
    'place': SealedField.text(),
    'date': SealedField.text(),
    'photo': SealedField.text(),
    'sound': SealedField.text(),
    'sound_meta': SealedField.text(),
  },
  'canvas_strokes': {'data': SealedField.json()},
  'mood_entries': {
    'mood_id': SealedField.text(),
    'label': SealedField.text(),
    'image_path': SealedField.text(),
  },
  'custom_moods': {'label': SealedField.text(), 'emoji': SealedField.text()},
  'love_tests': {'data': SealedField.json()},
  'widget_data': {
    'status': SealedField.text(),
    'mood_emoji': SealedField.text(),
    'mood_label': SealedField.text(),
    'message': SealedField.text(),
    'music_title': SealedField.text(),
    'music_artist': SealedField.text(),
    'music_url': SealedField.text(),
    'music_cover_url': SealedField.text(),
    'photo_url': SealedField.text(),
    'photo_for_partner_url': SealedField.text(),
    'photo_for_partner_urls': SealedField.json(),
    'photo_grid_urls': SealedField.json(),
    'data': SealedField.json(),
  },
  // Заряд телефона партнёру (lib/fork/battery/battery_share.dart).
  'fork_battery': {'state': SealedField.json()},
  'fork_reels_matches': {'state': SealedField.json()},
  'fork_movie_choices': {'state': SealedField.json()},
  // Текст «скучаю» пишет сервер (/api/group/miss-you) в запись, id которой
  // клиент не знает, — шифр привязан к паре и автору (`e2eRecordKey`).
  'miss_you': {'last_vibe_text': SealedField.text()},
  'miss_you_events': {'text': SealedField.text()},
  'groups': {
    // Профиль участников для партнёра: имя, аватар, карточка (баннер, пол,
    // день рождения) — каждый пишет своё (ForkE2E.publishProfile).
    'member_names': SealedField.mapValues(),
    'member_avatars': SealedField.mapValues(),
    'member_cards': SealedField.mapValues(),
    // Имя того, кто занимает пустое место, сервер берёт из его профиля — там
    // шифр чужого личного ключа: не откроется, видна заглушка.
    'claim_name': SealedField.text(),
    'member_moods': SealedField.mapValues(),
    'member_ailments': SealedField.mapValues(),
    'current_status': SealedField.json(),
    'custom_statuses': SealedField.json(),
    'timers': SealedField.json(),
    'custom_relationship_label': SealedField.text(),
    'custom_relationship_emoji': SealedField.text(),
    'custom_relationship_types': SealedField.json(),
    'member_birthdays': SealedField.mapValues(),
    // Пара с пустым местом: заглушка второго (имя, фото, дата возвращения).
    'placeholder_name': SealedField.text(),
    'placeholder_avatar': SealedField.text(),
    'return_date': SealedField.moved(),
    'daily_tasks': SealedField.json(),
    'chat_background': SealedField.text(),
    'mascots': SealedField.json(),
    'first_kiss_date': SealedField.moved(),
    // «Дни вместе» и годовщину телефон считает сам; серверу даты не нужны.
    'start_date': SealedField.moved(),
    'anniversary_date': SealedField.moved(),
  },
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

/// Писать нечем: ключа пары (или личного) нет, а в теле есть то, что уходит
/// только шифром. Запрос не отправляется — очередь повторит его, когда ключ
/// придёт. Открытым текстом не пишем никогда.
class E2ENoKeyError implements Exception {
  E2ENoKeyError(this.collection);
  final String collection;
  @override
  String toString() => 'E2ENoKeyError: нет ключа шифрования для $collection';
}

/// Дата в обязательной колонке, чьё значение переехало в `enc`.
const String e2eClearedDate = '2000-01-01 00:00:00.000Z';

/// Поле, которое не открылось (ключа ещё нет): шифртекст здесь, в колонке —
/// заглушка. Когда ключ придёт, [RecordCodec.retry] вернёт текст на место.
const String e2eLockedKey = 'e2e_locked';

/// Что видно вместо текста, пока ключа нет.
const String e2eLockedText = '🔒';

bool isSealedValue(Object? v) => v is String && v.startsWith(e2eFieldPrefix);

/// К чему привязан шифр записи: обычно её id. Текст «скучаю» сервер
/// раскладывает по записям сам, поэтому там — пара и автор.
String? e2eRecordKey(String collection, Map<String, dynamic> rec) {
  switch (collection) {
    case 'miss_you' || 'miss_you_events':
      final g = rec['group_id'], u = rec['user_uid'];
      if (g is! String || u is! String || g.isEmpty || u.isEmpty) return null;
      return '$g/$u';
    default:
      final id = rec['id'];
      return id is String ? id : null;
  }
}

/// Пара записи по телу запроса: у записи пары это она сама.
String? e2eGroupOf(String collection, String id, Map<String, dynamic> body) {
  // Запись пары — сама пара; свой профиль — личный ключ (группа = uid).
  if (collection == 'groups' || collection == 'users') {
    return id.isEmpty ? null : id;
  }
  final g = body['group_id'];
  return g is String && g.isNotEmpty ? g : null;
}

/// AAD поля: «скучаю» — одно место на обе коллекции, сервер копирует текст
/// из запроса и в счётчик, и в историю.
EnvelopePlace e2ePlace(String collection, String key, String field) =>
    switch (collection) {
      'miss_you' || 'miss_you_events' => RecordPlace('miss_you', key, 'text'),
      _ => RecordPlace(collection, key, field),
    };

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
        SealKind.json =>
          "(${e.key} != '' && ${e.key} != 'null' && ${e.key} != '[]' && "
              "${e.key} != '{}' && ${e.key} !~ '$e2eFieldPrefix')",
        SealKind.mapValues => "${e.key} ~ '\":{'",
        SealKind.jsonPartial =>
          "(${e.key} ~ '\":' && ${e.key} !~ '$e2eFieldPrefix')",
        SealKind.moved => switch (e.value.cleared) {
          final num n => '${e.key} != $n',
          final c => "(${e.key} != '' && ${e.key} != '$c')",
        },
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
        e2ePlace(collection, recordId, field),
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
          e2ePlace(collection, recordId, field),
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
      case SealKind.mapValues:
        return null;
    }
  }

  /// Строгое чтение: открытое значение в шифрованном поле написал не
  /// клиент (он без ключа не пишет вовсе), а сервер — его не показываем.
  /// Единственное открытое, что сервер пишет сам, — служебное воспоминание
  /// «Салют» из подарка (gifts.pb.js): фиксированный текст.
  static Map<String, dynamic> dropPlain(
    String collection,
    Map<String, dynamic> rec,
  ) {
    final fields = e2eFields[collection];
    if (fields == null || !hasPlainContent(collection, rec)) return rec;
    final out = Map<String, dynamic>.of(rec);
    for (final e in fields.entries) {
      final spec = e.value;
      if (!rec.containsKey(e.key) ||
          !hasPlainContent(collection, {
            e.key: rec[e.key],
            if (spec.kind == SealKind.moved) e2eMovedField: null,
          })) {
        continue;
      }
      final v = rec[e.key];
      switch (spec.kind) {
        case SealKind.text:
          out[e.key] = spec.locked ?? '';
        case SealKind.json:
          out[e.key] = spec.locked;
        case SealKind.moved:
          out[e.key] = spec.cleared;
        case SealKind.mapValues:
          out[e.key] = {
            for (final kv in (v as Map).entries)
              if (kv.value == null || isSealedValue(kv.value))
                '${kv.key}': kv.value,
          };
        case SealKind.jsonPartial:
          final m = v as Map;
          if (collection == 'memories' &&
              m['type'] == 'gift' &&
              m['giftKey'] == 'salute') {
            continue;
          }
          out[e.key] = {
            for (final kv in m.entries)
              if (spec.open.contains('${kv.key}') || kv.key == e2ePartialKey)
                '${kv.key}': kv.value,
          };
      }
    }
    return out;
  }

  /// Есть ли в теле [collection] открытое содержимое шифрованных полей —
  /// то, что без ключа ушло бы на сервер как есть.
  static bool hasPlainContent(String collection, Map<String, dynamic> body) {
    final fields = e2eFields[collection];
    if (fields == null) return false;
    for (final e in fields.entries) {
      final spec = e.value;
      if (!body.containsKey(e.key)) continue;
      final v = body[e.key];
      if (v == null || isSealedValue(v)) continue;
      if (spec.locked != null && v == spec.locked) continue;
      final has = switch (spec.kind) {
        SealKind.text => '$v'.isNotEmpty,
        SealKind.json => _plain(spec.kind, v) != null,
        SealKind.jsonPartial =>
          v is Map &&
              v[e2ePartialKey] == null &&
              v.entries.any(
                (kv) => kv.value != null && !spec.open.contains('${kv.key}'),
              ),
        SealKind.mapValues =>
          v is Map && v.values.any((x) => x != null && !isSealedValue(x)),
        SealKind.moved =>
          v != spec.cleared && !isSealedValue(body[e2eMovedField]),
      };
      if (has) return true;
    }
    return false;
  }

  /// Шифрует поля тела запроса записи [recordId] пары [groupId]. Нечего
  /// шифровать — тело как есть; есть что, а ключа нет — [E2ENoKeyError].
  Map<String, dynamic> encode(
    String collection,
    String recordId,
    String groupId,
    Map<String, dynamic> body, {
    Map<String, dynamic>? context,
  }) {
    final fields = e2eFields[collection];
    final key = _c == null ? null : keys.currentKey(groupId);
    // Для «скучаю» шифр привязан к паре и автору: их берём из тела или из
    // [context] (запись в кэше или на сервере).
    final recKey = e2eRecordKey(collection, {
      ...?context,
      ...body,
      'id': recordId,
    });
    if (fields == null) return body;
    if (key == null || recKey == null || recKey.isEmpty) {
      if (hasPlainContent(collection, body)) throw E2ENoKeyError(collection);
      return body;
    }
    final out = Map<String, dynamic>.of(body);
    final moved = <String, dynamic>{};
    for (final e in fields.entries) {
      if (e.value.kind == SealKind.moved) {
        // Поле есть в теле — значит его пишут, и null тоже: так дату стирают.
        // Заглушка (то, что видно без ключа) — не правка, её не трогаем.
        if (!out.containsKey(e.key) || isSealedValue(out[e2eMovedField])) {
          continue;
        }
        final v = out[e.key];
        if (v == e.value.cleared || (v != null && v == e.value.locked)) {
          continue;
        }
        moved[e.key] = v;
        out[e.key] = e.value.cleared;
        continue;
      }
      if (e.value.kind == SealKind.mapValues) {
        final v = out[e.key];
        if (v is! Map) continue;
        out[e.key] = {
          for (final kv in v.entries)
            kv.key.toString(): kv.value == null || isSealedValue(kv.value)
                ? kv.value
                : sealField(
                    collection,
                    recKey,
                    '${e.key}/${kv.key}',
                    jsonEncode(kv.value),
                    key,
                  ),
        };
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
          recKey,
          e.key,
          jsonEncode(rest),
          key,
        );
        out[e.key] = kept;
        continue;
      }
      final plain = _plain(e.value.kind, out[e.key]);
      if (plain == null) continue;
      out[e.key] = sealField(collection, recKey, e.key, plain, key);
    }
    if (moved.isNotEmpty) {
      final ctxLocked = context?[e2eLockedKey];
      if (ctxLocked is Map && ctxLocked.containsKey(e2eMovedField)) {
        // Прежний `enc` не открылся — переписать его значило бы стереть
        // остальные даты. Правка уходит в колонку как есть (она новее enc).
        for (final f in moved.keys) {
          out[f] = body[f];
        }
      } else {
        // `enc` один на все переехавшие поля: правка одной даты не должна
        // стереть другие — недостающие берём из записи (кэш или сервер).
        for (final e in fields.entries) {
          if (e.value.kind != SealKind.moved || moved.containsKey(e.key)) {
            continue;
          }
          final v = context?[e.key];
          if (v != null && v != '' && v != e.value.cleared) moved[e.key] = v;
        }
        out[e2eMovedField] = sealField(
          collection,
          recKey,
          e2eMovedField,
          jsonEncode(moved),
          key,
        );
      }
    }
    out.remove(e2eLockedKey);
    return out;
  }

  /// Приложение сохраняет запись, которую не смогло открыть: в теле —
  /// заглушки. Возвращаем на их место прежний шифр из [locked]
  /// (`e2e_locked` записи в кэше), чтобы не стереть содержимое на сервере.
  Map<String, dynamic> restoreLocked(
    String collection,
    Map<String, dynamic> body,
    Map<String, dynamic> locked,
  ) {
    final fields = e2eFields[collection];
    if (fields == null || locked.isEmpty) return body;
    final out = Map<String, dynamic>.of(body);
    for (final e in fields.entries) {
      final f = e.key, was = locked[f];
      if (was == null || !out.containsKey(f)) continue;
      final v = out[f];
      switch (e.value.kind) {
        case SealKind.text:
        case SealKind.json:
          if (v == e.value.locked || v == null || v == '') out[f] = was;
        case SealKind.jsonPartial:
          // Своё содержимое (не только служебные ключи) — это правка.
          if (v is Map &&
              v[e2ePartialKey] == null &&
              v.keys.every((k) => e.value.open.contains('$k')) &&
              was is Map &&
              was[e2ePartialKey] != null) {
            out[f] = {...v, e2ePartialKey: was[e2ePartialKey]};
          }
        case SealKind.mapValues:
          if (v is Map && was is Map) {
            out[f] = {
              for (final kv in was.entries)
                if (isSealedValue(kv.value) && !v.containsKey(kv.key))
                  '${kv.key}': kv.value,
              ...v.map((k, x) => MapEntry('$k', x)),
            };
          }
        case SealKind.moved:
          break;
      }
    }
    return out;
  }

  /// Расшифровывает поля записи с сервера. Не открылось — в поле заглушка,
  /// шифртекст уходит в [e2eLockedKey].
  Map<String, dynamic> decode(String collection, Map<String, dynamic> rec) {
    final fields = e2eFields[collection];
    final id = e2eRecordKey(collection, rec);
    if (fields == null || id == null) return rec;
    rec = dropPlain(collection, rec);
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
      if (e.value.kind != SealKind.mapValues) continue;
      final v = rec[e.key];
      if (v is! Map || !v.values.any(isSealedValue)) continue;
      out ??= Map<String, dynamic>.of(rec);
      final open = <String, dynamic>{};
      Map<String, dynamic>? bad;
      for (final kv in v.entries) {
        final k = kv.key.toString();
        if (!isSealedValue(kv.value)) {
          open[k] = kv.value;
          continue;
        }
        final plain = openField(
          collection,
          id,
          '${e.key}/$k',
          kv.value as String,
        );
        Object? value;
        var ok = plain != null;
        if (ok) {
          try {
            value = jsonDecode(plain);
          } on FormatException {
            ok = false;
          }
        }
        if (ok) {
          open[k] = value;
        } else {
          (bad ??= {})[k] = kv.value;
        }
      }
      out[e.key] = open;
      if (bad != null) (locked ??= {})[e.key] = {...open, ...bad};
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
          e.value.kind == SealKind.mapValues ||
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
