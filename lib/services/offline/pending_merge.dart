/// Слияние серверной версии записи с неотправленной своей правкой (RT-6).
///
/// Раньше дельта партнёра по записи, у которой в очереди лежит своя правка,
/// выбрасывалась целиком: «не перезатираем оптимистичное». Партнёр отметил
/// желание сбывшимся, а я в это время поменял его порядок — его отметка у
/// меня не появлялась, пока очередь не опустеет и не придёт ещё одна дельта
/// (а если моя операция на сервере ничего не меняла — не появлялась вовсе).
///
/// Теперь операция очереди говорит, какие поля она трогает ([pendingPathsOf]),
/// и серверная версия берётся целиком, кроме этих полей: их значение остаётся
/// своим, неотправленным. Поля E2E к этому моменту уже расшифрованы (дельты
/// декодирует `ForkE2E.decodeSync`, REST — http-клиент форка), поэтому путь
/// внутри частично шифрованного JSON (`memories.data`) — это ключ открытой
/// карты, а не шифртекста.
///
/// Операции, которые пишут запись целиком (upsert всей записи, удаление,
/// массовые правки), пофилдово не сливаются: сервер после их отправки сам
/// окажется в «моей» версии. Для них запись помечается отложенной, и после
/// отправки она перечитывается с сервера, а не считается окончательной.
library;

/// Путь поля: колонка записи и, для JSON-колонок, ключи внутри неё.
typedef FieldPath = List<String>;

/// Поля, которые трогает операция очереди [type]. `null` — операция пишет
/// запись целиком (или неизвестна), пофилдовое слияние невозможно.
///
/// Имена колонок совпадают с телом запроса в `PbDataService` и с ключами
/// кэша: в кэше лежит `RecordModel.toJson()` той же записи.
List<FieldPath>? pendingPathsOf(String type, Map<String, dynamic> p) {
  List<FieldPath> keysOf(Object? m) => [
    if (m is Map)
      for (final k in m.keys) [k.toString()],
  ];
  String s(Object? v) => v?.toString() ?? '';

  switch (type) {
    // ── группа: колонки и словари «участник → значение» ──
    case 'groupUpdateFields':
      return keysOf(p['cols']);
    case 'groupSetStatus':
      return [
        ['current_status'],
      ];
    case 'groupSetMemberMood':
      return [
        ['member_moods', s(p['uid'])],
      ];
    case 'groupSetMemberAilment':
      return [
        ['member_ailments', s(p['uid'])],
      ];
    case 'counterInc':
      return [
        [s(p['field'])],
      ];
    // ── чат: правка шлёт только свои колонки, реакция — свой ключ ──
    case 'chatUpdate':
      return keysOf(p['fields']);
    case 'chatSetReaction':
      return [
        ['reactions', s(p['uid'])],
      ];
    // ── желание: отметка шлёт только свои колонки (см. wishMarkBody) ──
    case 'wishMark':
      return keysOf(p['fields']);
    // ── воспоминание: сервер правит `data` по ключу (RMW свежей записи) ──
    case 'memorySetSaved':
      return [
        ['data', 'savedBy'],
      ];
    case 'memorySetReaction':
      return [
        ['data', 'reactions', s(p['uid'])],
      ];
    case 'memoryBumpComments':
      return [
        ['data', 'commentsCount'],
      ];
    case 'memorySticker':
      return [
        ['data', 'stickers', s(p['sid'])],
      ];
    default:
      return null;
  }
}

/// Неотправленная операция очереди: тип и тело, как их хранит outbox.
typedef PendingOp = ({String type, Map<String, dynamic> payload});

/// Итог слияния: [merged] — что положить в кэш; `null` — слить нельзя
/// (операция пишет запись целиком), кэш оставляем своим.
class PendingMerge {
  const PendingMerge(this.merged);
  final Map<String, dynamic>? merged;
}

/// Серверная [server] версия записи поверх своей [local] с неотправленными
/// [ops]: всё серверное, кроме полей, которые трогают операции.
///
/// Нет локальной записи — брать «своё» неоткуда, слияние невозможно.
PendingMerge mergeOverPending({
  required Map<String, dynamic> server,
  required Map<String, dynamic>? local,
  required Iterable<PendingOp> ops,
}) {
  if (local == null) return const PendingMerge(null);
  final paths = <FieldPath>[];
  for (final op in ops) {
    final p = pendingPathsOf(op.type, op.payload);
    if (p == null) return const PendingMerge(null);
    paths.addAll(p.where((path) => path.isNotEmpty && path.first.isNotEmpty));
  }
  final out = _deepCopy(server) as Map<String, dynamic>;
  for (final path in paths) {
    _copyPath(from: local, into: out, path: path);
  }
  return PendingMerge(out);
}

/// Переложить значение по [path] из [from] в [into]. Нет значения в [from] —
/// убрать его и из [into] (своя правка его удалила). Промежуточный уровень в
/// [into] не карта — заменяем картой: своя правка там знает больше.
void _copyPath({
  required Map<String, dynamic> from,
  required Map<String, dynamic> into,
  required FieldPath path,
}) {
  Object? src = from;
  for (final k in path) {
    src = src is Map ? (src.containsKey(k) ? src[k] : _absent) : _absent;
    if (identical(src, _absent)) break;
  }
  var dst = into;
  for (var i = 0; i < path.length - 1; i++) {
    final k = path[i];
    final next = dst[k];
    if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      dst[k] = copy;
      dst = copy;
    } else {
      if (identical(src, _absent)) return; // удалять нечего
      final fresh = <String, dynamic>{};
      dst[k] = fresh;
      dst = fresh;
    }
  }
  if (identical(src, _absent)) {
    dst.remove(path.last);
  } else {
    dst[path.last] = _deepCopy(src);
  }
}

const Object _absent = Object();

Object? _deepCopy(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): _deepCopy(e.value),
    };
  }
  if (v is List) return [for (final e in v) _deepCopy(e)];
  return v;
}

/// `updated` записи: PocketBase пишет `2026-10-29 10:00:00.000Z`, такие
/// строки сравниваются лексикографически = хронологически.
String recordUpdated(Map<String, dynamic>? rec) =>
    (rec?['updated'] ?? '').toString();

/// Версия [incoming] не старее [current]: её можно класть поверх, ничего
/// свежего не откатив. Без `updated` с любой стороны (оптимистичная запись,
/// старый кэш) судить не по чему — кладём, как раньше.
bool isNotOlder({
  required Map<String, dynamic>? current,
  required Map<String, dynamic> incoming,
}) {
  final cur = recordUpdated(current);
  final inc = recordUpdated(incoming);
  if (cur.isEmpty || inc.isEmpty) return true;
  return inc.compareTo(cur) >= 0;
}
