/// Поиск по зашифрованной переписке (PLAN S9).
///
/// Сервер текста не видит, и `text ~ 'слово'` ему больше не по силам. Здесь
/// листаем историю пары страницами (каждая расшифровывается по дороге, см.
/// [E2EHttpClient]) и ищем у себя. Вкладки без текста — голосовые, кружки,
/// воспоминания — по-прежнему ищет сервер.
library;

import 'package:pocketbase/pocketbase.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/chat_search.dart';
import '../../services/pocketbase_service.dart';

/// Насколько полон ответ [ForkChatSearch.search]: экран говорит об этом,
/// чтобы «ничего не нашлось» не значило «просмотрели не всё».
class ForkSearchScan {
  /// Связь оборвалась посреди истории: часть переписки не просмотрена.
  bool interrupted = false;

  /// Дошли до предела [ForkChatSearch.scanLimit], а история ещё есть.
  bool capped = false;

  bool get incomplete => interrupted || capped;
}

/// Что сказать, если [ForkSearchScan.incomplete].
String get forkSearchGapText => ruEn(
  'Просмотрена не вся переписка (обрыв связи или слишком длинная история) — '
      'результат может быть неполным.',
  'Not the whole chat was searched (connection dropped or the history is '
      'too long) — results may be incomplete.',
);

abstract final class ForkChatSearch {
  /// Сколько сообщений просматриваем за один запрос экрана.
  static const int scanLimit = 10000;
  static const int _pageSize = 200;

  /// Нужен ли локальный поиск для вкладки [kind] пары [groupId]. Текст
  /// запроса серверу не уходит никогда — даже у пары без ключа.
  static bool applies(String groupId, ChatSearchKind kind) =>
      kind == ChatSearchKind.all || kind == ChatSearchKind.links;

  /// Совпадает ли сообщение с запросом — так же, как искал сервер.
  static bool matches(ChatSearchKind kind, String text, String query) {
    final t = text.toLowerCase();
    final q = query.trim().toLowerCase();
    switch (kind) {
      case ChatSearchKind.all:
        return q.length >= kChatSearchMinChars && t.contains(q);
      case ChatSearchKind.links:
        return t.contains('http') &&
            (q.length < kChatSearchMinChars || t.contains(q));
      default:
        return false;
    }
  }

  /// До [limit] найденных сообщений старше [beforeTs], новые первыми.
  /// null — сервер не ответил.
  static Future<List<RecordModel>?> search({
    required String groupId,
    required ChatSearchKind kind,
    required String query,
    int? beforeTs,
    int limit = 40,
    PocketBase? pb,
    ForkSearchScan? scan,
  }) async {
    final client = pb ?? PocketBaseService().pb;
    final out = <RecordModel>[];
    var before = beforeTs;
    var scanned = 0;
    try {
      while (out.length < limit && scanned < scanLimit) {
        final page = await client
            .collection('chat_messages')
            .getList(
              perPage: _pageSize,
              sort: '-ts',
              skipTotal: true,
              filter: client.filter(
                'group_id = {:g} && deleted != true'
                '${before == null ? '' : ' && ts < {:t}'}',
                {'g': groupId, 't': ?before},
              ),
            );
        if (page.items.isEmpty) break;
        for (final r in page.items) {
          if (matches(kind, r.getStringValue('text'), query)) {
            out.add(r);
            if (out.length >= limit) break;
          }
        }
        scanned += page.items.length;
        before = page.items.last.getIntValue('ts');
        if (page.items.length < _pageSize) break;
        if (scanned >= scanLimit && out.length < limit) scan?.capped = true;
      }
    } catch (_) {
      scan?.interrupted = true;
      return out.isEmpty ? null : out;
    }
    return out;
  }
}
