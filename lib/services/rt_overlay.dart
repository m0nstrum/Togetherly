import 'package:pocketbase/pocketbase.dart';

import 'offline/pending_merge.dart';

/// Живая дельта, отложенная до конца загрузки списка (RT-4).
typedef BufferedDelta = ({String action, RecordModel record});

/// Наложить дельты, пришедшие, пока шла загрузка, на её снимок [byId].
///
/// Подписка ставится ДО загрузки, иначе изменения между ответом сервера и
/// подпиской терялись навсегда. Но снимок мог быть снят и позже дельты —
/// тогда в нём уже версия новее, и наложение откатило бы её. Поэтому дельта
/// кладётся, только если она не старее записи снимка (по `updated`); удаление
/// — если запись в снимке не новее удалённой версии.
void overlayDeltas(
  Map<String, RecordModel> byId,
  Iterable<BufferedDelta> deltas,
) {
  for (final d in deltas) {
    final id = d.record.id;
    final cur = byId[id];
    final incoming = d.record.toJson();
    if (cur != null && !isNotOlder(current: cur.toJson(), incoming: incoming)) {
      continue;
    }
    if (d.action == 'delete') {
      byId.remove(id);
    } else {
      byId[id] = d.record;
    }
  }
}

/// Ответ сервера [loaded] против последней дельты [delta] того же документа,
/// пришедшей, пока шёл запрос: побеждает более свежая версия (RT-4).
/// Возвращает, что показать, и удалён ли документ.
({RecordModel? record, bool gone}) pickFresher({
  required RecordModel? loaded,
  required BufferedDelta? delta,
}) {
  if (delta == null) return (record: loaded, gone: loaded == null);
  if (loaded != null &&
      !isNotOlder(current: loaded.toJson(), incoming: delta.record.toJson())) {
    return (record: loaded, gone: false);
  }
  if (delta.action == 'delete') return (record: null, gone: true);
  return (record: delta.record, gone: false);
}
