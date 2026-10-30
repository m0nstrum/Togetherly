import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../fork/memories/search.dart'; // fork: D10
import '../../models/feed_category.dart';
import '../../models/memory.dart';
import '../../models/memory_sort.dart';
import '../../models/on_this_day.dart';
import '../../services/locale_service.dart';
import '../../services/memory_repository.dart';
import '../../services/pocketbase_service.dart';
import '../../services/ui_prefs.dart';

/// Filter mode for Memory Lane pinned memories.
enum MemoryFilterMode { none, day, month }

/// Лента воспоминаний без виджетов: живая подписка, порядок, тег-фильтры,
/// поиск, раскрытые секреты и окно ленивой пагинации (A12-2).
///
/// Поля фильтров экран меняет сам внутри своего `setState`, как и раньше.
/// Слушателей контроллер зовёт только на то, что приходит асинхронно: лента
/// из подписки, ошибка подписки, прочитанный из prefs порядок.
class MemoryFeedController extends ChangeNotifier {
  MemoryFeedController({
    required this.filterMode,
    Stream<List<Memory>> Function(String groupId)? watch,
    String? Function()? myUid,
    Future<String?> Function()? loadSort,
    Future<void> Function(String value)? saveSort,
    DateTime Function()? now,
  }) : _watch = watch ?? MemoryRepository().watch,
       _myUid = myUid ?? (() => PocketBaseService().userId),
       _loadSort = loadSort ?? UiPrefs.memorySort,
       _saveSort = saveSort ?? UiPrefs.setMemorySort,
       _now = now ?? DateTime.now;

  final Stream<List<Memory>> Function(String groupId) _watch;
  final String? Function() _myUid;
  final Future<String?> Function() _loadSort;
  final Future<void> Function(String value) _saveSort;
  final DateTime Function() _now;

  final MemoryFilterMode filterMode;

  List<Memory> memories = [];
  bool loading = true;

  /// Чем упорядочена лента. Выбор человека живёт в prefs: он про привычку, а
  /// не про конкретный заход.
  MemorySort sortOrder = MemorySort.eventDate;

  // Ленивая пагинация ленты: рендерим окно из последних N воспоминаний и растим
  // его по мере прокрутки. Данные все в кэше — это окно ПО UI, не по сети.
  static const int pageSize = 30;
  int visibleLimit = pageSize;

  // ── Фильтр-теги ленты (этап 2 редизайна) ───────────────────────────────────
  // «Моменты» = фото+видео (общий бейдж «Момент»); остальные категории —
  // один-в-один к `_typeBadgeMeta` экрана. null = «Всё». [favoritesOnly] —
  // независимый круглый тег слева: показывает только личные закладки (savedBy).
  String? categoryKey;
  bool favoritesOnly = false;

  /// Строка поиска: сравнивается с названием, подписью и местом записи.
  String searchQuery = '';

  /// Секретные воспоминания раскрыты в этой сессии экрана (после ввода PIN).
  /// Сбрасывается при выходе с экрана — секреты снова прячутся.
  bool secretUnlocked = false;

  StreamSubscription<List<Memory>>? _sub;
  bool _disposed = false;

  Future<void> loadSortOrder() async {
    final saved = await _loadSort();
    if (_disposed) return;
    sortOrder = memorySortFromName(saved);
    notifyListeners();
  }

  Future<void> setSortOrder(MemorySort order) async {
    sortOrder = order;
    notifyListeners();
    await _saveSort(order.name);
  }

  /// Живая подписка на ленту воспоминаний (PocketBase SSE). Заменяет
  /// пагинацию/cache-first: на self-hosted PB чтения бесплатны → вся лента
  /// приезжает разом и обновляется в реальном времени (свои и партнёрские
  /// добавления/правки/удаления — без кнопок «обновить»/«загрузить ещё»).
  ///
  /// [onData] зовётся после того, как лента обновлена и слушатели оповещены.
  void subscribe(String groupId, {void Function(List<Memory>)? onData}) {
    if (groupId.isEmpty) {
      loading = false;
      notifyListeners();
      return;
    }
    _sub?.cancel();
    _sub = _watch(groupId).listen(
      (list) {
        if (_disposed) return;
        memories = list;
        loading = false;
        notifyListeners();
        onData?.call(list);
      },
      onError: (e) {
        debugPrint('memory_lane: watch error: $e');
        if (_disposed) return;
        loading = false;
        notifyListeners();
      },
    );
  }

  /// Категории, реально присутствующие в ленте (чтобы не показывать пустые теги).
  List<FeedCategory> get presentCategories => presentFeedCategories(memories);

  bool get feedFiltered => favoritesOnly || categoryKey != null;

  /// Проходит ли воспоминание текущий тег-фильтр (категория + «Избранное»).
  bool passesFeedFilter(Memory m) {
    // Секретные скрыты из ленты, пока не введён PIN (см. [secretUnlocked]).
    if (m.isSecret && !secretUnlocked) return false;
    if (favoritesOnly && !m.isSavedBy(_myUid() ?? '')) return false;
    if (!matchesQuery(m)) return false;
    if (categoryKey == null) return true;
    final cat = kFeedCategories.firstWhere(
      (c) => c.key == categoryKey,
      orElse: () => kFeedCategories.first,
    );
    return cat.matches(m);
  }

  /// Подходит ли запись под строку поиска. Пустой запрос пропускает всё.
  bool matchesQuery(Memory m) {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    // fork: D10 — ищем и по песням, книгам, фильмам
    return memoryMatchesQuery(m, q);
  }

  bool get hasVisibleMemories =>
      pinnedMemories.isNotEmpty || groupedByDate.isNotEmpty;

  /// Подрастить окно ленты. false — расти некуда.
  bool growWindow() {
    if (!canShowMore) return false;
    visibleLimit += pageSize;
    return true;
  }

  List<Memory>? _otdSource;
  DateTime? _otdDay;
  List<OnThisDayShelf> _otdCache = const [];

  /// Полка «В этот день». Пересчёт только при новой ленте или смене дня:
  /// лента пересобирается на каждое касание, а записей бывают тысячи.
  List<OnThisDayShelf> get onThisDayShelves {
    final now = _now();
    final day = DateTime(now.year, now.month, now.day);
    if (!identical(_otdSource, memories) || _otdDay != day) {
      _otdSource = memories;
      _otdDay = day;
      _otdCache = onThisDay(memories, now: now);
    }
    return _otdCache;
  }

  List<Memory> get pinnedMemories {
    if (filterMode != MemoryFilterMode.none) return [];
    return memories.where((m) => m.isPinned && passesFeedFilter(m)).toList();
  }

  /// Memories filtered by current day/month across all years, grouped by year
  Map<String, List<Memory>> get filteredByDateAcrossYears {
    final now = _now();
    List<Memory> filtered;
    if (filterMode == MemoryFilterMode.day) {
      filtered = memories
          .where(
            (m) => m.createdAt.month == now.month && m.createdAt.day == now.day,
          )
          .toList();
    } else if (filterMode == MemoryFilterMode.month) {
      filtered = memories.where((m) => m.createdAt.month == now.month).toList();
    } else {
      return {};
    }
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final Map<String, List<Memory>> grouped = {};
    for (var m in filtered) {
      final key = '${m.createdAt.year}';
      grouped.putIfAbsent(key, () => []).add(m);
    }
    return grouped;
  }

  /// Все непин-воспоминания, прошедшие фильтр, новые первыми (без окна).
  ///
  /// Порядок выбирает человек: по дате события (когда это случилось) или по
  /// дате добавления. Просьба тестера — «добавьте сортировку по указанной
  /// дате»: фотография со свадьбы, занесённая сегодня, уезжала в конец ленты.
  List<Memory> get nonPinnedSortedAll {
    if (filterMode != MemoryFilterMode.none) return const [];
    return memories.where((m) => !m.isPinned && passesFeedFilter(m)).toList()
      // Срок капсулы передаём в сортировку: с днём открытия капсула
      // становится сегодняшним событием и поднимается наверх, иначе человек
      // получал уведомление и не находил её в ленте (жалоба 31.08.2026).
      ..sort(
        (a, b) => compareMemories(
          sortOrder,
          aEvent: a.createdAt,
          bEvent: b.createdAt,
          aAdded: a.addedAt,
          bAdded: b.addedAt,
          aOpenAt: a.openAt,
          bOpenAt: b.openAt,
        ),
      );
  }

  /// Есть ли воспоминания за пределами текущего окна (для подгрузки по скроллу).
  bool get canShowMore =>
      filterMode == MemoryFilterMode.none &&
      nonPinnedSortedAll.length > visibleLimit;

  /// Group non-pinned memories by date, newest first — ОКНО ([visibleLimit]).
  Map<String, List<Memory>> get groupedByDate {
    if (filterMode != MemoryFilterMode.none) return {};
    final Map<String, List<Memory>> grouped = {};
    for (final m in nonPinnedSortedAll.take(visibleLimit)) {
      grouped.putIfAbsent(dateKey(m.createdAt), () => []).add(m);
    }
    return grouped;
  }

  String dateKey(DateTime dt) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    final s = LocaleService.current;
    if (diff == 0) return s.todayDate;
    if (diff == 1) return s.yesterday;
    if (diff < 7) return s.shortWeekdays[dt.weekday - 1];

    final months = s.shortMonths;
    if (dt.year == now.year) {
      return '${months[dt.month - 1]} ${dt.day}';
    }
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// Встроенный режим (превью на главном): первые [n] записей ленты.
  List<Memory> previewMemories(int n) {
    final all = <Memory>[
      ...pinnedMemories,
      ...nonPinnedSortedAll,
    ].where((m) => !m.isSecret || secretUnlocked).toList();
    return all.length > n ? all.sublist(0, n) : all;
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
