import 'package:characters/characters.dart';
import 'package:home_widget/home_widget.dart';

import '../../models/canvas_meta.dart';
import '../../models/countdown_widget.dart';
import '../../models/mood_entry.dart';
import '../../models/mood_widget_payload.dart';
import '../../models/pair_data.dart';
import '../../models/timer_item.dart';
import '../../models/user_data.dart';
import '../../services/canvas/canvas_widget_service.dart';
import '../../services/canvas_repository.dart';
import '../../services/canvas_storage_service.dart';
import '../../services/home_widget_service.dart';
import '../../services/locale_service.dart';
import '../../services/map/pair_map_widget_service.dart';
import '../../services/mascot_service.dart';
import '../../services/mood_service.dart';
import '../../services/timer_service.dart';
import '../../services/widget_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/couple_days.dart';
import '../../widgets/draw/canvas_preview.dart';
import 'preview_style.dart';

/// Запись данных пары в виджеты рабочего стола.
///
/// Снимок того, что знает экран виджетов в момент синхронизации: экран
/// собирает его заново перед каждым вызовом, поэтому счётчики и холсты
/// всегда свежие, а сам класс ничего не хранит между вызовами.
class WidgetDataSync {
  WidgetDataSync({
    required this.user,
    required this.pair,
    required this.ws,
    required this.moods,
    required this.timers,
    required this.mascot,
    required this.theme,
    required this.ps,
    required this.widgetTimer,
    required this.togetherStart,
    required this.memoriesCount,
    required this.drawingsCount,
    required this.missYouCount,
    required this.missCounts,
    required this.canvases,
  });

  final UserData user;
  final PairData pair;
  final WidgetService ws;
  final MoodService moods;
  final TimerService timers;
  final MascotService mascot;
  final AppTheme theme;
  final PreviewStyle ps;

  /// Таймер, выбранный для виджета «Таймер».
  final TimerItem? widgetTimer;

  /// Начало отношений — то же, что в превью каталога.
  final DateTime? togetherStart;
  final int? memoriesCount;
  final int? drawingsCount;
  final int? missYouCount;

  /// uid → сколько раз скучал.
  final Map<String, int> missCounts;
  final List<CanvasMeta> canvases;

  AppStrings get _s => LocaleService.current;
  String get partnerGender => ws.firstPartnerData?.gender ?? '';

  /// Под каким ключом Kotlin ищет группу нового виджета типа [widgetType]
  /// (`<ключ>_next_bind_group`); `null` — привязка не нужна.
  ///
  /// Фото-виджеты получают группу через свою конфигурацию, а «Серия» живёт
  /// на общих ключах: ветка по умолчанию перехватила бы привязку таймера.
  static String? pinBindKey(String? widgetType) {
    if (widgetType == null ||
        widgetType.startsWith('photo_day') ||
        widgetType == 'streak') {
      return null;
    }
    return switch (widgetType) {
      // Оба оформления заметки — один и тот же виджет, отличается только
      // стиль: он и уходит отдельным ключом.
      'note' || 'note_paper' => 'note',
      'petal_timer' => 'petal_timer',
      'days_counter' => 'days_counter',
      'mood' => 'mood',
      'stats' || 'relationship_stats' => 'stats',
      // Новый каталог: Kotlin ждёт together_/miss_. Без этих веток
      // привязка уходила в timer_next_bind_group и перехватывала группу
      // у виджета «Таймер», а сами новые виджеты оставались без группы.
      'together' => 'together',
      'miss' => 'miss',
      'year_ring' => 'year_ring',
      'mascot' => 'mascot',
      'canvas' => 'canvas',
      'year_grid' => 'year_grid',
      'map' => 'map',
      // Парный виджет тоже помнит свою связь: до 04.09.2026 он один на все
      // пары показывал ту, что открыта в приложении последней. Ключ зовётся
      // по ТИПУ виджета (`pair_next_bind_group`) — его и ищет
      // WidgetGroupHelper, — а сами данные лежат под `love_<пара>_<поле>`.
      'pair' => 'pair',
      _ => 'timer', // 'timer' and others
    };
  }

  /// Save next_bind_group so Kotlin picks it up on first onUpdate.
  Future<void> saveBindGroup(String? widgetType) async {
    final bindTypeKey = pinBindKey(widgetType);
    if (bindTypeKey == null) return;
    await HomeWidget.saveWidgetData<String>(
      '${bindTypeKey}_next_bind_group',
      pair.pairId,
    );
    if (bindTypeKey == 'note') {
      await HomeWidget.saveWidgetData<String>(
        'note_next_style',
        widgetType == 'note_paper' ? 'paper' : 'm3',
      );
    }
  }

  /// Обновлять ли фото-виджет с группой [widgetGroupId] из пары [pairId].
  /// For solo mode, sync widgets without group or with empty group.
  static bool photoDayInGroup(String pairId, String? widgetGroupId) =>
      pairId.isEmpty
      ? (widgetGroupId == null || widgetGroupId.isEmpty)
      : (widgetGroupId == pairId || widgetGroupId == null);

  /// Высота столбика настроения в процентах; день без отметки — -1.
  static int moodBarPercent(MoodEntry? e) =>
      e == null ? -1 : (((e.score - 1) / 4) * 80 + 20).round().clamp(20, 100);

  /// Неделя для «Настроения»: семь пар «моё/партнёра» от понедельника недели
  /// [today] и число дней, где оценки совпали. [theirs] — `null` без пары.
  static ({List<List<int>> week, int matched}) moodWeek(
    DateTime today, {
    required MoodEntry? Function(DateTime day) mine,
    MoodEntry? Function(DateTime day)? theirs,
  }) {
    final week = <List<int>>[];
    var matched = 0;
    // От понедельника этой недели к воскресенью.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final my = mine(day);
      final their = theirs?.call(day);
      week.add([moodBarPercent(my), moodBarPercent(their)]);
      if (my != null && their != null && my.score == their.score) {
        matched++;
      }
    }
    return (week: week, matched: matched);
  }

  /// Сразу после пина записывает данные текущей группы в виджет.
  Future<void> afterPin(String widgetType) async {
    final hws = HomeWidgetService.instance;
    switch (widgetType) {
      case 'days_counter':
        // Используем тот же алгоритм выбора таймера, что и Timer-виджет,
        // чтобы Days Counter всегда показывал дни того же таймера.
        final activeTimer = await hws.resolveActiveTimerPublic(
          timers.timers,
          pair.pairId,
        );
        final timer = activeTimer ?? timers.systemTimer ?? timers.defaultTimer;
        final start = timer?.startDate ?? pair.startDate;
        final emoji = timer?.emoji ?? pair.relationshipEmoji;
        final days = timer != null
            ? timer.daysElapsed.abs()
            : (start != null ? calendarDaysBetween(start, DateTime.now()) : 0);
        final startLabel = start != null
            ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
            : '';
        final names = pair.partnerName.isNotEmpty ? pair.partnerName : '';
        await hws.syncDaysCounter(
          groupId: pair.pairId,
          daysCount: days,
          coupleNames: names,
          emoji: emoji,
          startDate: startLabel,
          start: start,
          myGender: user.gender?.name ?? '',
          partnerGender: ws.firstPartnerData?.gender ?? '',
        );
        break;
      case 'miss':
        await miss();
        break;
      case 'together':
        // Дни — из активного таймера, как и у остальных счётчиков.
        final timer = timers.defaultTimer ?? timers.systemTimer;
        final start = timer?.startDate ?? pair.startDate;
        final days = timer != null
            ? timer.daysElapsed.abs()
            : (start != null ? calendarDaysBetween(start, DateTime.now()) : 0);
        final startLabel = start == null
            ? ''
            : _s.tgYearSince('${_s.dayLogDate(start)} ${start.year}');
        final myName = user.displayName.trim();
        final partnerName = pair.partnerDisplayName.trim();
        final anniversary = start == null ? '' : _s.dayLogDate(start);
        await hws.syncTogether(
          groupId: pair.pairId,
          days: days,
          startDate: startLabel,
          start: start,
          myInitial: myName.isEmpty
              ? ''
              : myName.characters.first.toUpperCase(),
          partnerInitial: partnerName.isEmpty
              ? ''
              : partnerName.characters.first.toUpperCase(),
          names: [myName, partnerName].where((n) => n.isNotEmpty).join(' + '),
          anniversary: anniversary,
          myAvatarUrl: user.avatarUrl,
          partnerAvatarUrl: pair.partnerAvatarUrl,
        );
        break;
      case 'timer':
      case 'petal_timer':
        final timer = widgetTimer;
        if (timer != null) await hws.syncTimer(timer, groupId: pair.pairId);
        break;
      case 'photo_day_self':
      case 'photo_day_partner':
      case 'photo_day':
        // Ждём, пока система зарегистрирует новый виджет (requestPinWidget возвращает
        // управление сразу, а ID появляется только когда пользователь бросает виджет
        // на рабочий стол). Без задержки новый виджет ещё не виден в getPhotoDayWidgetIds.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final ids = await hws.getPhotoDayWidgetIds();
        // Передаём kind явно, чтобы не было race condition когда Kotlin ещё
        // не записал kind='partner' в SharedPreferences через assignConfig().
        final partnerIds = (await hws.getPartnerPhotoWidgetIds()).toSet();
        for (final widgetId in ids) {
          final widgetGroupId = await hws.getPhotoDayWidgetGroupId(widgetId);
          final shouldSync = photoDayInGroup(pair.pairId, widgetGroupId);
          if (shouldSync) {
            await hws.refreshPhotoOfDay(
              pair.pairId,
              widgetId: widgetId,
              overrideKind: partnerIds.contains(widgetId) ? 'partner' : null,
            );
          }
        }
        if (ids.isEmpty) {
          await hws.refreshPhotoOfDay(pair.pairId);
        }
        break;
      case 'photo_grid':
        // Photo grid requires a group (partner), skip for solo mode
        if (pair.pairId.isNotEmpty) {
          await hws.refreshPhotoGrid(pair.pairId);
        }
        break;
      case 'mood_tiles':
        await moodTiles();
        break;
      case 'countdown':
        await countdown();
        break;
      case 'pair':
        // Парный виджет синхронизируется WidgetService
        break;
      case 'mood':
        // Ждём, пока система зарегистрирует новый виджет перед синхронизацией.
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        // Синхронизируем из Mood Calendar за сегодня
        {
          final today = DateTime.now();
          final myEntries = moods.myEntriesForDay(today);
          final myEntry = myEntries.isNotEmpty ? myEntries.first : null;
          final partnerUid = pair.partners.isNotEmpty
              ? pair.partners.first.uid
              : '';
          final partnerEntries = partnerUid.isNotEmpty
              ? moods.partnerEntriesForDay(partnerUid, today)
              : <MoodEntry>[];
          final partnerEntry = partnerEntries.isNotEmpty
              ? partnerEntries.first
              : null;
          // Записи за сегодня главнее, иначе последнее известное настроение из
          // widget_data — то же правило, что на главном экране; см.
          // moodHalfPayload.
          final mine = moodHalfPayload(
            entry: myEntry,
            widgetMoodEmoji: ws.myData?.moodEmoji ?? '',
            widgetMoodLabel: ws.myData?.moodLabel ?? '',
            gender: user.gender?.name ?? '',
          );
          final theirs = moodHalfPayload(
            entry: partnerEntry,
            widgetMoodEmoji: ws.firstPartnerData?.moodEmoji ?? '',
            widgetMoodLabel: ws.firstPartnerData?.moodLabel ?? '',
            gender: ws.firstPartnerData?.gender ?? '',
          );
          await hws.syncMood(
            groupId: pair.pairId,
            moodEmojiAssetPath: mine.imagePath,
            moodLabel: mine.label,
            moodScore: mine.score,
            moodColor: mine.colorHex,
            userName: ws.myData?.displayName ?? '',
            partnerMoodEmojiAssetPath: theirs.imagePath,
            partnerMoodLabel: theirs.label,
            partnerMoodColor: theirs.colorHex,
            partnerMoodScore: theirs.score,
            partnerUserName: pair.partnerName,
            noMoodText: _s.noMoodRecorded,
            nameFallbackMe: _s.me,
            nameFallbackPartner: _s.partner,
            ratingPrefix: _s.moodScorePrefix,
          );
        }
        break;
      case 'relationship_stats':
        // «Дни вместе» от ОСНОВНОГО (дефолтного) таймера — как Days Counter и
        // круг; системный таймер хранит дату пары (≈сегодня) → давал бы 0.
        final relTimer = timers.defaultTimer ?? timers.systemTimer;
        final start = relTimer?.startDate ?? pair.startDate;
        await hws.syncRelationshipStats(
          groupId: pair.pairId,
          daysTogether: start != null
              ? calendarDaysBetween(start, DateTime.now())
              : 0,
          memoriesCount: memoriesCount ?? 0,
          drawingsCount: drawingsCount ?? 0,
          missYouCount: missYouCount ?? 0,
          daysLabel: LocaleService.current.daysTogetherStat,
          memoriesLabel: LocaleService.current.memoriesStat,
          drawingsLabel: LocaleService.current.drawingsStat,
          missYouLabel: LocaleService.current.missYousStat,
        );
        break;
      case 'map':
        // Картинка нарисуется, когда виджет встанет на стол: лончер разбудит
        // Dart. Здесь — имена, аватарки и тема для фоновой отрисовки.
        await PairMapWidgetService.instance.refreshFromApp(
          groupId: pair.pairId,
          myUid: user.uid,
          partnerUid: pair.partnerUid,
          myName: user.displayName,
          partnerName: pair.partnerDisplayName,
          myAvatarUrl: user.avatarUrl,
          partnerAvatarUrl: pair.partnerAvatarUrl,
          theme: theme,
        );
        break;
      case 'year_ring':
      case 'year_grid':
        await years();
        break;
      case 'mascot':
        // Кадры режет сервис маскота: у него и персонаж, и серия, и окно сна.
        mascot.resyncStreakWidget();
        break;
      case 'canvas':
        await canvas();
        break;
    }
  }

  /// Данные «Кольца года» и «Календаря лет».
  ///
  /// Дата начала — от основного таймера, как у остальных счётчиков: системный
  /// таймер держит дату регистрации пары и дал бы почти нулевой стаж.
  Future<void> years() async {
    final start = togetherStart;
    await HomeWidgetService.instance.syncYearWidgets(
      groupId: pair.pairId,
      start: start,
      memoriesCount: memoriesCount ?? 0,
      startDateLabel: start == null ? '' : _s.tgYearSince(ps.formatDate(start)),
    );
  }

  Future<void> canvas() async {
    if (canvases.isEmpty) return;
    await CanvasWidgetService.instance.publish(
      groupId: pair.pairId,
      canvases: canvases,
      activeId: canvases.first.id,
      strokesOf: (meta) => pair.pairId.isEmpty
          ? CanvasStorageService.instance.loadLocalStrokes(user.uid, meta.id)
          : CanvasRepository.instance.previewStrokes(
              pair.pairId,
              meta.id,
              limit: kPreviewStrokeLimit,
            ),
    );
  }

  /// Отдаём виджету «Настроение» сегодняшние отметки обоих и неделю.
  ///
  /// Неделя — семь пар «моё/партнёра» в процентах высоты столбика. Балл
  /// настроения в приложении от 1 до 5, поэтому переводим его в проценты;
  /// день без отметки уезжает как -1 и рисуется пустой подложкой, а не нулём:
  /// «не отмечался» и «было плохо» — разные вещи.
  Future<void> moodTiles() async {
    final today = DateTime.now();
    final partnerUid = pair.partnerUid;

    MoodEntry? entryOf(List<MoodEntry> list) =>
        list.isNotEmpty ? list.first : null;

    final w = moodWeek(
      today,
      mine: (day) => entryOf(moods.myEntriesForDay(day)),
      theirs: partnerUid.isEmpty
          ? null
          : (day) => entryOf(moods.partnerEntriesForDay(partnerUid, day)),
    );

    final myToday = entryOf(moods.myEntriesForDay(today));
    final partnerToday = partnerUid.isEmpty
        ? null
        : entryOf(moods.partnerEntriesForDay(partnerUid, today));

    await HomeWidgetService.instance.syncMoodTiles(
      groupId: pair.pairId,
      myLabel: myToday == null ? '' : myToday.labelFor(MoodGenders.mine),
      myMoodId: myToday?.moodId ?? '',
      partnerLabel: partnerToday == null
          ? ''
          : partnerToday.labelFor(partnerGender),
      partnerName: pair.partnerDisplayName.trim(),
      week: w.week,
      matchedDays: w.matched,
    );
  }

  /// Отдаём виджету «До встречи» ближайшие обратные отсчёты. Остаток виджет
  /// считает сам; полоса идёт от даты пары.
  Future<void> countdown() async {
    await HomeWidgetService.instance.syncCountdownEvents(
      groupId: pair.pairId,
      events: countdownEventsFor(
        timers.timers,
        now: DateTime.now(),
        dateLabel: ps.formatDayMonth,
      ),
      from: togetherStart,
    );
  }

  /// Отдаём виджету «Скучаю» свежие счётчики обоих.
  Future<void> miss() async {
    final partnerName = pair.partnerDisplayName.trim();
    await HomeWidgetService.instance.syncMiss(
      groupId: pair.pairId,
      myCount: missCounts[user.uid] ?? 0,
      partnerCount: missCounts[pair.partnerUid] ?? 0,
      partnerName: partnerName,
      partnerInitial: partnerName.isEmpty
          ? ''
          : partnerName.characters.first.toUpperCase(),
      partnerAvatarUrl: pair.partnerAvatarUrl,
    );
  }
}
