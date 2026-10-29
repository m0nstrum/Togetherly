import 'package:pocketbase/pocketbase.dart';

import 'local_store.dart';
import 'outbox_service.dart';
import 'pending_merge.dart';

/// Одна страница серверной выдачи: [filter] — уже с условием на водяной знак,
/// сортировка по `updated` — забота вызывающего.
typedef ScopePageFetch =
    Future<ResultList<RecordModel>> Function(String filter, int page);

/// Инкрементальная синхронизация области: при первом разе — постранично всё,
/// далее — только `updated > водяной_знак`.
///
/// Водяной знак двигается ТОЛЬКО здесь, по ответу сервера (RT-1). Живая
/// дельта знак не трогает: после обрыва сокета первая же новая дельта ставила
/// его на своё `updated`, следующий запрос спрашивал `updated > знак`, и всё,
/// что сервер записал за обрыв, не приходило больше никогда.
///
/// [afterWatermark] строит условие `updated > {знак}` с экранированием
/// (`pb.filter`), [cancelled] прерывает обход страниц. [onDeferred] узнаёт
/// id записей с неотправленной правкой: их серверная версия легла в кэш
/// лишь слиянием (или не легла вовсе), и после отправки правки запись надо
/// перечитать — водяной знак её уже миновал.
Future<void> syncScopeIncremental({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required String token,
  required String baseFilter,
  required String Function(String watermark) afterWatermark,
  required ScopePageFetch fetchPage,
  bool Function()? cancelled,
  void Function(String id)? onDeferred,
}) async {
  bool isCancelled() => cancelled?.call() ?? false;
  final wm = await store.lastUpdated(token);
  String maxU = wm ?? '';
  final String pageFilter;
  if (wm == null) {
    pageFilter = baseFilter;
  } else {
    final wmCond = afterWatermark(wm);
    pageFilter = baseFilter.isEmpty ? wmCond : '($baseFilter) && ($wmCond)';
  }
  var page = 1;
  while (!isCancelled()) {
    final res = await fetchPage(pageFilter, page);
    if (res.items.isEmpty) break;
    // Запись с неотправленной правкой не перезатираем, а сливаем: поля своей
    // правки остаются своими, остальное — серверное (RT-6). Водяной знак
    // двигаем по ВСЕМ; такие записи после отправки перечитает [onDeferred].
    final toApply = <RecordModel>[];
    for (final r in res.items) {
      if (outbox.isPending(collection, r.id)) {
        await applyOverPending(
          store: store,
          outbox: outbox,
          collection: collection,
          record: r,
        );
        onDeferred?.call(r.id);
      } else {
        toApply.add(r);
      }
    }
    // Свежее, уже пришедшее живой дельтой, страница не откатывает (RT-4).
    if (toApply.isNotEmpty) {
      await store.applyDelta(collection, toApply, skipOlder: true);
    }
    for (final r in res.items) {
      final u = r.data['updated'];
      if (u is String && u.compareTo(maxU) > 0) maxU = u;
    }
    if (page >= res.totalPages) break;
    page++;
  }
  if (maxU.isNotEmpty && (wm == null || maxU.compareTo(wm) > 0)) {
    await store.setLastUpdated(token, maxU);
  }
}

/// Живая дельта сокета — только в кэш, водяной знак не трогаем (см.
/// [syncScopeIncremental]): запись, уже пришедшая дельтой, при следующем
/// запросе к серверу придёт ещё раз, зато пропущенное за обрыв — тоже.
///
/// Дельта старее того, что уже в кэше, не кладётся: она могла задержаться,
/// пока страница сервера уже принесла версию новее (RT-4). Запись с
/// неотправленной правкой сливается с дельтой по полям ([applyOverPending]),
/// а [onDeferred] узнаёт её id, чтобы перечитать после отправки.
Future<void> applyLiveDelta({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required String action,
  required RecordModel record,
  void Function(String id)? onDeferred,
}) async {
  if (outbox.isPending(collection, record.id)) {
    // Удаление партнёром поверх своей правки не применяем: что победит,
    // решит сервер, а запись перечитаем после отправки.
    if (action != 'delete') {
      await applyOverPending(
        store: store,
        outbox: outbox,
        collection: collection,
        record: record,
      );
    }
    onDeferred?.call(record.id);
    return;
  }
  if (action == 'delete') {
    await store.deleteRecord(collection, record.id);
    return;
  }
  final incoming = record.toJson();
  await store.updateRaw(
    collection,
    record.id,
    (cur) => isNotOlder(current: cur, incoming: incoming) ? incoming : null,
  );
}

/// Серверная версия [record] поверх своей записи с неотправленной правкой:
/// поля правки остаются своими, остальное — серверное ([mergeOverPending]).
/// Операция пишет запись целиком — кэш не трогаем, как раньше.
Future<void> applyOverPending({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required RecordModel record,
}) async {
  final ops = outbox.pendingOps(collection, record.id);
  final server = record.toJson();
  await store.updateRaw(collection, record.id, (local) {
    // Запоздавший ответ или дельта старее того, что уже слито в кэш, не
    // откатывает чужие поля к прежней версии.
    if (!isNotOlder(current: local, incoming: server)) return null;
    return mergeOverPending(server: server, local: local, ops: ops).merged;
  });
}

/// Правка покинула очередь: запись перечитываем с сервера, а не считаем
/// свою версию окончательной (RT-6). [fetch] — `getOne` записи, `null` —
/// записи на сервере нет. Отравленную правку не трогаем: её запись живёт в
/// кэше до повтора, и пустой ответ сервера стёр бы её вместе с кнопкой
/// «Повторить». [cancelled] — подписка снята, пока ждали ответа; кэш
/// очищен (выход из аккаунта) — ответ тоже выбрасывается
/// ([LocalStore.generation]).
Future<void> refetchSettled({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required String id,
  required Future<RecordModel?> Function(String id) fetch,
  bool Function()? cancelled,
}) async {
  if (outbox.isPoisoned(collection, id)) return;
  final generation = store.generation;
  final rec = await fetch(id);
  if ((cancelled?.call() ?? false) || store.generation != generation) return;
  // Пока ждали ответа, легла новая правка — её очередь снова перечитает.
  if (outbox.isPending(collection, id) || outbox.isPoisoned(collection, id)) {
    return;
  }
  if (rec == null) {
    await store.deleteRecord(collection, id);
  } else {
    await applyLiveDelta(
      store: store,
      outbox: outbox,
      collection: collection,
      action: 'update',
      record: rec,
    );
  }
}
