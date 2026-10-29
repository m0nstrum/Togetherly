import 'package:pocketbase/pocketbase.dart';

import 'local_store.dart';
import 'outbox_service.dart';

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
/// (`pb.filter`), [cancelled] прерывает обход страниц.
Future<void> syncScopeIncremental({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required String token,
  required String baseFilter,
  required String Function(String watermark) afterWatermark,
  required ScopePageFetch fetchPage,
  bool Function()? cancelled,
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
    // Не перезатираем записи с неотправленными локальными правками
    // (водяной знак двигаем по ВСЕМ, т.к. их серверный `updated` всё равно
    // старый — после отправки правки строка получит новый `updated` и
    // до-синхронизируется инкрементом).
    final toApply = res.items
        .where((r) => !outbox.isPending(collection, r.id))
        .toList();
    if (toApply.isNotEmpty) await store.applyDelta(collection, toApply);
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
Future<void> applyLiveDelta({
  required LocalStore store,
  required OutboxService outbox,
  required String collection,
  required String action,
  required RecordModel record,
}) async {
  // Запись с неотправленной правкой не трогаем — до-синхронизируется после
  // отправки правки.
  if (outbox.isPending(collection, record.id)) return;
  if (action == 'delete') {
    await store.deleteRecord(collection, record.id);
  } else {
    await store.upsert(collection, record);
  }
}
