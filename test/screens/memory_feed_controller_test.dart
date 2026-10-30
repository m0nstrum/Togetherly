import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/memory_sort.dart';
import 'package:love_app/screens/memory_lane/feed_controller.dart';
import 'package:love_app/services/locale_service.dart';

/// A12-2: лента воспоминаний без виджетов — фильтры, порядок, окно,
/// подписка. Заменяет чтение полей экрана как текста.
void main() {
  final now = DateTime(2026, 10, 30, 12);

  Memory m(
    String id, {
    DateTime? at,
    DateTime? added,
    MemoryType type = MemoryType.text,
    String? title,
    bool pinned = false,
    bool secret = false,
    List<String>? savedBy,
  }) => Memory(
    id: id,
    groupId: 'g',
    authorUid: 'me',
    authorName: 'Аня',
    type: type,
    createdAt: at ?? now,
    addedAt: added,
    title: title,
    isPinned: pinned,
    isSecret: secret,
    savedBy: savedBy,
  );

  MemoryFeedController feed({
    MemoryFilterMode mode = MemoryFilterMode.none,
    Stream<List<Memory>> Function(String)? watch,
    Future<String?> Function()? loadSort,
    Future<void> Function(String)? saveSort,
  }) => MemoryFeedController(
    filterMode: mode,
    watch: watch ?? (_) => const Stream.empty(),
    myUid: () => 'me',
    loadSort: loadSort ?? () async => null,
    saveSort: saveSort ?? (_) async {},
    now: () => now,
  );

  List<String> ids(Iterable<Memory> list) => [for (final x in list) x.id];

  group('фильтры', () {
    test('секрет скрыт до PIN, закреплённые — отдельно', () {
      final c = feed()
        ..memories = [m('a', pinned: true), m('b', secret: true), m('c')];
      expect(ids(c.pinnedMemories), ['a']);
      expect(ids(c.nonPinnedSortedAll), ['c']);
      c.secretUnlocked = true;
      expect(ids(c.nonPinnedSortedAll), ['b', 'c']);
    });

    test('«Избранное», категория и поиск складываются', () {
      final c = feed()
        ..memories = [
          m('fav', title: 'Море', savedBy: ['me']),
          m('other', title: 'Море', savedBy: ['partner']),
          m('song', type: MemoryType.music, title: 'Песня'),
        ];
      expect(c.feedFiltered, isFalse);

      c.favoritesOnly = true;
      expect(c.feedFiltered, isTrue);
      expect(ids(c.nonPinnedSortedAll), ['fav']);

      c
        ..favoritesOnly = false
        ..categoryKey = 'music';
      expect(ids(c.nonPinnedSortedAll), ['song']);

      c
        ..categoryKey = null
        ..searchQuery = '  мор ';
      expect(ids(c.nonPinnedSortedAll), ['fav', 'other']);
    });

    test('категории — только те, что есть в ленте', () {
      final c = feed()..memories = [m('song', type: MemoryType.music)];
      expect([for (final x in c.presentCategories) x.key], ['music']);
    });
  });

  test('порядок: по событию или по дате добавления', () {
    final c = feed()
      ..memories = [
        m('old', at: DateTime(2020), added: DateTime(2026, 10, 29)),
        m('new', at: DateTime(2026, 10, 1), added: DateTime(2026, 1, 1)),
      ];
    expect(ids(c.nonPinnedSortedAll), ['new', 'old']);
    c.sortOrder = MemorySort.addedAt;
    expect(ids(c.nonPinnedSortedAll), ['old', 'new']);
  });

  test('порядок читается из prefs и сохраняется туда', () async {
    final saved = <String>[];
    final c = feed(
      loadSort: () async => 'addedAt',
      saveSort: (v) async => saved.add(v),
    );
    var notified = 0;
    c.addListener(() => notified++);

    await c.loadSortOrder();
    expect(c.sortOrder, MemorySort.addedAt);
    expect(notified, 1);

    await c.setSortOrder(MemorySort.eventDate);
    expect(c.sortOrder, MemorySort.eventDate);
    expect(saved, ['eventDate']);
    expect(notified, 2);
  });

  test('окно ленты растёт страницами, пока есть что показать', () {
    final c = feed()
      ..memories = [
        for (var i = 0; i < 45; i++)
          m('m$i', at: DateTime(2025, 1, 1).add(Duration(days: i))),
      ];
    int shown() => c.groupedByDate.values.fold(0, (n, l) => n + l.length);

    expect(shown(), MemoryFeedController.pageSize);
    expect(c.canShowMore, isTrue);
    expect(c.growWindow(), isTrue);
    expect(shown(), 45);
    expect(c.canShowMore, isFalse);
    expect(c.growWindow(), isFalse);
    expect(c.visibleLimit, 2 * MemoryFeedController.pageSize);
  });

  test('группы по дням: сегодня, вчера, день недели, дата', () {
    final s = LocaleService.current;
    final c = feed();
    expect(c.dateKey(now), s.todayDate);
    expect(c.dateKey(now.subtract(const Duration(days: 1))), s.yesterday);
    final third = now.subtract(const Duration(days: 3));
    expect(c.dateKey(third), s.shortWeekdays[third.weekday - 1]);
    expect(c.dateKey(DateTime(2026, 3, 5)), '${s.shortMonths[2]} 5');
    expect(c.dateKey(DateTime(2024, 3, 5)), '${s.shortMonths[2]} 5, 2024');
  });

  test('режим «день» и «месяц» — по всем годам, группы по году', () {
    final list = [
      m('day24', at: DateTime(2024, 10, 30)),
      m('day25', at: DateTime(2025, 10, 30)),
      m('month', at: DateTime(2025, 10, 2)),
      m('other', at: DateTime(2025, 9, 30)),
    ];
    final day = feed(mode: MemoryFilterMode.day)..memories = list;
    expect(day.filteredByDateAcrossYears.keys, ['2025', '2024']);
    expect(ids(day.filteredByDateAcrossYears.values.expand((l) => l)), [
      'day25',
      'day24',
    ]);
    // В режимах дня и месяца обычная лента и закреплённые пусты.
    expect(day.groupedByDate, isEmpty);
    expect(day.pinnedMemories, isEmpty);
    expect(day.canShowMore, isFalse);

    final month = feed(mode: MemoryFilterMode.month)..memories = list;
    expect(ids(month.filteredByDateAcrossYears['2025']!), ['day25', 'month']);

    expect((feed()..memories = list).filteredByDateAcrossYears, isEmpty);
  });

  test('превью на главной: закреплённые первыми, не больше N', () {
    final c = feed()
      ..memories = [
        m('a', at: DateTime(2026, 10, 1)),
        m('b', at: DateTime(2026, 10, 2)),
        m('pin', pinned: true, at: DateTime(2020)),
      ];
    expect(ids(c.previewMemories(2)), ['pin', 'b']);
    expect(ids(c.previewMemories(10)), ['pin', 'b', 'a']);
  });

  test('«В этот день» пересчитывается только с новой лентой', () {
    final c = feed()..memories = [m('y', at: DateTime(2025, 10, 30))];
    final first = c.onThisDayShelves;
    expect(first, isNotEmpty);
    expect(identical(c.onThisDayShelves, first), isTrue);
    c.memories = [m('none', at: DateTime(2025, 1, 1))];
    expect(c.onThisDayShelves, isEmpty);
  });

  group('подписка', () {
    test('лента приходит, слушатели и onData — по порядку', () async {
      final ctrl = StreamController<List<Memory>>();
      final groups = <String>[];
      final c = feed(
        watch: (g) {
          groups.add(g);
          return ctrl.stream;
        },
      );
      final events = <String>[];
      c.addListener(() => events.add('notify:${c.memories.length}'));
      c.subscribe('g1', onData: (l) => events.add('data:${l.length}'));
      expect(c.loading, isTrue);

      ctrl.add([m('a'), m('b')]);
      await pumpEventQueue();
      expect(groups, ['g1']);
      expect(c.loading, isFalse);
      expect(events, ['notify:2', 'data:2']);
      c.dispose();
      await ctrl.close();
    });

    test('пустая группа — сразу не грузится, без подписки', () {
      var watched = false;
      final c = feed(
        watch: (_) {
          watched = true;
          return const Stream.empty();
        },
      );
      var notified = 0;
      c
        ..addListener(() => notified++)
        ..subscribe('');
      expect(watched, isFalse);
      expect(c.loading, isFalse);
      expect(notified, 1);
    });

    test('ошибка подписки снимает загрузку', () async {
      final c = feed(watch: (_) => Stream.error(StateError('нет сети')));
      c.subscribe('g');
      await pumpEventQueue();
      expect(c.loading, isFalse);
      expect(c.memories, isEmpty);
    });

    test('после dispose лента не меняется', () async {
      final ctrl = StreamController<List<Memory>>.broadcast();
      final c = feed(watch: (_) => ctrl.stream)..subscribe('g');
      c.dispose();
      expect(ctrl.hasListener, isFalse);
      ctrl.add([m('late')]);
      await pumpEventQueue();
      expect(c.memories, isEmpty);
      await ctrl.close();
    });
  });
}
