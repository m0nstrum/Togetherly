// B9: статистика пары не показывает шифр. Сервер считает по колонкам, а
// часть из них — шифр (docs/E2E.md): такие поля клиент подменяет сам.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/services/couple_stats_service.dart';
import 'package:love_app/services/watch_history_service.dart';

WatchEntry _w(String kind) =>
    WatchEntry(id: 'x', url: '', kind: kind, title: '', thumb: '', seconds: 0);

/// Ключ ответа `/api/couple/stats` → откуда сервер его берёт: «коллекция.колонка»
/// (колонка обязана быть открытой в кодеке), `count` — только число записей,
/// `patched` — значение шифр, клиент подменяет его своим.
const Map<String, List<String>> _sources = {
  'ok': ['count'],
  'couple': ['count'],
  'created': ['groups.created_at'],
  'start': ['patched'],
  'anniversary': ['patched'],
  'streak': ['groups.streak_days'],
  'xp': ['groups.xp'],
  'members': ['groups.members'],
  'uid': ['groups.members', 'miss_you.user_uid'],
  'name': ['patched'],
  'totals': ['count'],
  'memories': ['memories.author_uid', 'memories.created_at'],
  'comments': ['count'],
  'messages': ['chat_messages.user_uid', 'chat_messages.ts'],
  'moods': ['mood_entries.user_uid', 'mood_entries.timestamp'],
  'missYou': ['miss_you.user_uid', 'miss_you.count'],
  'strokes': ['count'],
  'canvases': ['count'],
  'gifts': ['gifts.sender_uid', 'gifts.gift_key'],
  'watch': ['count'],
  'media': ['media.file'],
  'videos': ['media.file'],
  'photos': ['media.file'],
  'mascots': ['count'],
  'byMember': ['count'],
  'timeline': ['count'],
  'rhythm': ['count'],
  'weekdayMessages': ['chat_messages.ts'],
  'hourMessages': ['chat_messages.ts'],
  'weekdayMemories': ['memories.created_at'],
  'mood': ['patched'],
  'daily': ['patched'],
  'top': ['patched'],
  'breakdown': ['count'],
  'memoryTypes': ['memories.type'],
  'watchKinds': ['patched'],
  'missYouWeekday': ['miss_you.by_weekday'],
  'w': ['miss_you.by_weekday'],
  'pace': ['count'],
  'memories30': ['memories.created_at'],
  'memories90': ['memories.created_at'],
  'messages30': ['chat_messages.ts'],
  'messages90': ['chat_messages.ts'],
  'moods30': ['mood_entries.timestamp'],
  'activeDays30': ['chat_messages.ts'],
  'firstMemory': ['memories.created_at'],
};

/// Где и как клиент подменяет шифр-поле.
const Map<String, (String, String)> _patches = {
  'start': ('lib/fork/e2e/fork_e2e.dart', "couple['start']"),
  'anniversary': ('lib/fork/e2e/fork_e2e.dart', "couple['anniversary']"),
  'name': ('lib/fork/e2e/fork_e2e.dart', "m['name']"),
  'mood': ('lib/services/couple_stats_service.dart', "json['mood']"),
  'daily': ('lib/services/couple_stats_service.dart', "'daily':"),
  'top': ('lib/services/couple_stats_service.dart', "'top':"),
  'watchKinds': (
    'lib/services/couple_stats_service.dart',
    "breakdown['watchKinds']",
  ),
};

void main() {
  test('площадки просмотров — из расшифрованной истории, частые сверху', () {
    final json = watchKindsJson([
      _w('youtube'),
      _w('rutube'),
      _w('youtube'),
      _w('e2e1.k.n.ct'),
      _w(e2eLockedText),
    ]);
    expect(json, [
      {'k': 'youtube', 'c': 2},
      {'k': 'rutube', 'c': 1},
    ]);
    final stats = CoupleStats.fromJson({
      'breakdown': {'watchKinds': json},
    });
    expect(stats.watchKinds, {'youtube': 2, 'rutube': 1});
  });

  test('имена участников — из member_names пары, шифр не показывается', () {
    final json = <String, dynamic>{
      'couple': {'start': '', 'anniversary': ''},
      'members': [
        {'uid': 'a', 'name': 'e2e1.personal.cipher'},
        {'uid': 'b', 'name': 'e2e1.other'},
        {'uid': 'c', 'name': 'e2e1.third'},
      ],
    };
    ForkE2E.patchCoupleStatsFrom({
      'start_date': '2024-02-14 00:00:00.000Z',
      'anniversary_date': '',
      'member_names': {'a': 'Аня', 'b': 'e2e1.not.opened', 'c': e2eLockedText},
    }, json);
    final stats = CoupleStats.fromJson(json);
    expect(stats.members, {'a': 'Аня', 'b': '', 'c': ''});
    expect(stats.startDate, DateTime.utc(2024, 2, 14));
  });

  test('каждое поле ответа статистики открыто в кодеке или подменяется', () {
    final go = File(
      'server/internal/usecase/stats/stats.go',
    ).readAsStringSync();
    final fn = go.split('func (s *Service) CoupleStats(')[1];
    final keys = <String>{
      for (final m in RegExp(r'"(\w+)":').allMatches(fn)) m.group(1)!,
      for (final m in RegExp(r'out\["(\w+)"\]').allMatches(fn)) m.group(1)!,
      for (final m in RegExp(r'json:"(\w+)"').allMatches(fn)) m.group(1)!,
    };
    expect(keys, contains('watchKinds'), reason: 'разбор stats.go сломался');
    for (final k in keys) {
      final src = _sources[k];
      expect(
        src,
        isNotNull,
        reason:
            'новое поле ответа «$k»: опишите в _sources, '
            'откуда оно и не шифр ли там',
      );
      for (final s in src!) {
        if (s == 'count') continue;
        if (s == 'patched') {
          final (file, mark) = _patches[k]!;
          expect(
            File(file).readAsStringSync(),
            contains(mark),
            reason: '«$k» — шифр, а клиент его не подменяет ($file)',
          );
          continue;
        }
        final [col, field] = s.split('.');
        expect(
          e2eFields[col]?[field],
          isNull,
          reason:
              '«$k» сервер считает по $s, а это шифр: '
              'подмените на клиенте и отметьте patched',
        );
      }
    }
  });

  test('подменяемые поля и правда шифр — иначе подмена лишняя', () {
    expect(e2eFields['users']?['display_name'], isNotNull);
    expect(e2eFields['watch_history']?['kind'], isNotNull);
    expect(e2eFields['mood_entries']?['mood_id'], isNotNull);
    expect(e2eFields['groups']?['start_date'], isNotNull);
  });
}
