import '../fork/ui/manual_widget_hint.dart';
import '../fork/widget_pin_confirmation.dart';
import '../fork/ui/feedback.dart'; // fork (PLAN 2.2)
import '../fork/identity.dart'; // fork: полное имя класса виджета
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/mood_image.dart';
import '../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../theme/fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import '../services/pb_media_service.dart';
import '../services/widget_anim_service.dart';
import '../services/plus_service.dart';
import '../services/ui_prefs.dart';
import '../dict_strings.dart' show ruEn, trKey, zhForEnglishIfZh;
import '../models/widget_panels.dart';
import '../widgets/miss_widget_card.dart';
import '../widgets/together_track_card.dart';
import '../services/widget_theme_sync.dart';
import '../models/pair_map_widget_view.dart';
import '../services/map/pair_map_widget_service.dart';
import '../widgets/map/pair_map_widget_preview.dart';
import 'plus_screen.dart';
import '../utils/couple_days.dart';
import '../utils/safe_pick.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logic/photo_day_widget_logic.dart';
import '../models/pair_data.dart';
import '../models/symbol_catalog.dart';
import '../models/timer_item.dart';
import '../models/widget_data.dart';
import '../models/year_progress.dart';
import '../models/user_data.dart';
import '../models/mood_entry.dart';
import '../models/memory.dart';
import '../services/media_service.dart';
import '../services/pocketbase_service.dart';
import '../services/rewarded_ad_service.dart';
import '../services/pb_auth_service.dart';
import '../services/pb_data_service.dart';
import '../services/memory_repository.dart';
import '../services/miss_you_repository.dart';
import '../services/home_widget_service.dart';
import '../services/level_service.dart';
import '../services/locale_service.dart';
import '../utils/photo_crop.dart';
import '../services/mood_notification_service.dart';
import '../services/mood_service.dart';

import '../models/canvas_meta.dart';
import '../services/canvas_storage_service.dart';
import '../services/mascot_service.dart';
import '../services/timer_service.dart';
import '../services/widget_rotation.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';
import '../widgets/pair_preview_divider.dart';
import 'home/widgets/mood_picker_dialog.dart';
import 'home/widgets/photo_day_carousel_editor.dart';
import 'home/widgets/memory_photo_picker.dart';
import 'postcard/postcard_editor_screen.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/widget_content_view.dart';
import 'widget_screen/text_editor_sheet.dart';
import 'widget_screen/photo_source_sheet.dart';
import 'widget_screen/photo_destination_sheet.dart';
import 'widget_screen/music_editor_sheet.dart';
import 'widget_screen/catalog.dart';
import 'widget_screen/catalog_panels.dart';
import 'widget_screen/controls.dart';
import 'widget_screen/preview_parts.dart';
import 'widget_screen/preview_style.dart';
import 'widget_screen/previews_time.dart';
import 'widget_screen/previews_pair.dart';
import 'widget_screen/previews_misc.dart';
import 'widget_screen/widget_data_sync.dart';

/// Экран виджетов — два тайла (мой / партнёра) + настройки автоотправки.
class WidgetScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final WidgetService widgetService;
  final MoodService moodService;
  final TimerService timerService;
  final MascotService mascotService;
  final AppTheme theme;

  /// Открыт по тапу на парный виджет рабочего стола — сразу разворачиваем
  /// карточку «Парный виджет» и прокручиваем к ней (правка фото/музыки и т.д.).
  final bool openPairEditorOnStart;

  const WidgetScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.widgetService,
    required this.moodService,
    required this.timerService,
    required this.mascotService,
    required this.theme,
    this.openPairEditorOnStart = false,
  });

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen>
    with WidgetsBindingObserver {
  /// Реклама за пробу «наших фото»: один экземпляр на экран.
  final RewardedAdService _rewardedAd = RewardedAdService();

  AppTheme get _t => widget.theme;
  ColorScheme get _cs => ProfileTheme.themeFor(_t).colorScheme;
  PreviewStyle get _ps => PreviewStyle(_cs);
  WidgetService get _ws => widget.widgetService;

  /// Текст заметки на двоих — тот самый, что лежит на рабочем столе.
  ///
  /// В превью каталога был зашит образец про молоко, и человек, написавший
  /// «Спасибо», видел в приложении прежнюю рыбу: «текст на заметке не
  /// меняется» (жалоба 20.09.2026).
  String _noteText = '';
  String _noteAuthor = '';
  String _noteAt = '';
  MoodService get _moodService => widget.moodService;
  TimerService get _timerService => widget.timerService;
  MascotService get _mascotService => widget.mascotService;
  PairData get _pair => widget.pairData;
  AppStrings get _s => LocaleService.current;

  /// Что раскрыто на экране и какие размеры выбраны в карточках.
  final WidgetCatalogPanels _panels = WidgetCatalogPanels();

  bool get _pairWidgetExpanded => _panels.isExpanded(WidgetPanels.pairWidget);
  bool get _petalTimerWidgetExpanded =>
      _panels.isExpanded(WidgetPanels.petalTimer);
  bool get _daysCounterExpanded => _panels.isExpanded(WidgetPanels.daysCounter);
  bool get _photoDayExpanded => _panels.isExpanded(WidgetPanels.photoDay);
  bool get _partnerPhotoExpanded =>
      _panels.isExpanded(WidgetPanels.partnerPhoto);
  bool get _photoGridExpanded => _panels.isExpanded(WidgetPanels.photoGrid);

  /// Свернуть или раскрыть и тут же запомнить решение.
  void _togglePanel(String key) => _panels.toggle(key);

  void _onPanelsChanged() {
    if (mounted) setState(() {});
  }

  // Скролл галереи + ключ карточки «Парный виджет» — чтобы прокрутить к ней
  // при открытии по тапу на виджет рабочего стола.
  final ScrollController _galleryScrollController = ScrollController();
  final GlobalKey _pairWidgetKey = GlobalKey();

  bool _canPinWidgets = false;
  Timer? _pinConfirmationTimer;
  late final _pinConfirmation = ForkWidgetPinConfirmation(
    installed: HomeWidget.getInstalledWidgets,
    confirmed: () async {
      await LevelService.instance.award(XpAction.setWidget);
      await UiPrefs.markWidgetPinned();
      if (mounted)
        ForkNotice.info(context, LocaleService.current.widgetAddedToHome);
    },
  );

  Future<void> _checkPinnedWidgets() async {
    try {
      await _pinConfirmation.check();
    } catch (_) {
      /* Retry on resume. */
    }
    if (!_pinConfirmation.pending) _pinConfirmationTimer?.cancel();
  }

  // Счётчик дней: персонализация «наши фото» (фича за коины)
  // Цена — зеркало FEATURE_PRICES['days_widget_photos'] на сервере.
  static const int _daysPhotosPrice = 20;
  bool _daysPhotosEnabled = false;
  bool _daysPhotosBusy = false;
  String? _widgetTimerId;

  int? _memoriesCount;
  int? _drawingsCount;
  int? _missYouCount;

  /// uid → сколько раз скучал. Виджету «Скучаю» нужны оба числа по отдельности.
  Map<String, int> _missCounts = const {};
  StreamSubscription? _missYouSub;
  Timer? _loadPhotoDayDebounce;

  // Экран блокировки: настроение
  bool _lockScreenMoodEnabled = false;

  // Фото-сетка
  int _photoGridCount = 1; // МОЁ количество (для настройки)
  List<String> _photoGridPaths = []; // локальные пути МОИХ фото (для выбора)
  bool _isLoadingPhotoGrid = false;

  // Фото-виджет (личный) и Фото партнёра — две независимые карточки
  bool _savePhotoAsMemory = true;

  /// Подмешивать в «Фото партнёра» его снимки из заданий дня.
  bool _partnerTaskPhotos = false;

  List<int> _personalWidgetIds = [];
  List<int> _partnerWidgetIds = [];
  Map<int, String> _photoDayWidgetNames = const {};
  Map<int, String?> _photoDayWidgetOwnPhotoPaths = const {};
  // Per-widget кеш URL-ов (длина → счётчик в превью)
  Map<int, List<String>> _photoDayWidgetUrls = const {};
  // Per-widget настройки ротации (для подсказок в превью)
  Map<int, String> _photoDayWidgetRotationType = const {};
  Map<int, int> _photoDayWidgetRotationInterval = const {};

  int? _selectedPersonalWidgetId;
  int? _selectedPartnerWidgetId;

  String get _widgetTimerKey => 'widget_timer_id_${_pair.pairId}';

  /// Холсты пары для карточки «Рисунок на столе». Подгружаются один раз:
  /// каталог открывают, чтобы поставить виджет, а не смотреть галерею.
  List<CanvasMeta> _canvases = [];

  static const String _heartSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="m11.645 20.91-.007-.003-.022-.012a15.247 15.247 0 0 1-.383-.218 25.18 25.18 0 0 1-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0 1 12 5.052 5.5 5.5 0 0 1 16.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 0 1-4.244 3.17 15.247 15.247 0 0 1-.383.219l-.022.012-.007.004-.003.001a.752.752 0 0 1-.704 0l-.003-.001Z" /></svg>''';
  static const String _calendarSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M6.75 2.25A.75.75 0 0 1 7.5 3v1.5h9V3A.75.75 0 0 1 18 3v1.5h.75a3 3 0 0 1 3 3v11.25a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3V7.5a3 3 0 0 1 3-3H6V3a.75.75 0 0 1 .75-.75Zm13.5 9a1.5 1.5 0 0 0-1.5-1.5H5.25a1.5 1.5 0 0 0-1.5 1.5v7.5a1.5 1.5 0 0 0 1.5 1.5h13.5a1.5 1.5 0 0 0 1.5-1.5v-7.5Z" clip-rule="evenodd" /></svg>''';
  static const String _timerSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25ZM12.75 6a.75.75 0 0 0-1.5 0v6c0 .414.336.75.75.75h4.5a.75.75 0 0 0 0-1.5h-3.75V6Z" clip-rule="evenodd" /></svg>''';
  static const String _photoSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M1.5 6a2.25 2.25 0 0 1 2.25-2.25h16.5A2.25 2.25 0 0 1 22.5 6v12a2.25 2.25 0 0 1-2.25 2.25H3.75A2.25 2.25 0 0 1 1.5 18V6ZM3 16.06V18c0 .414.336.75.75.75h16.5A.75.75 0 0 0 21 18v-1.94l-2.69-2.689a1.5 1.5 0 0 0-2.12 0l-.88.879.97.97a.75.75 0 1 1-1.06 1.06l-5.16-5.159a1.5 1.5 0 0 0-2.12 0L3 16.061Zm10.125-7.81a1.125 1.125 0 1 1 2.25 0 1.125 1.125 0 0 1-2.25 0Z" clip-rule="evenodd" /></svg>''';
  static const String _moodSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-2.625 6c-.54 0-.828.419-.936.634a1.96 1.96 0 0 0-.189.866c0 .298.059.605.189.866.108.215.395.634.936.634.54 0 .828-.419.936-.634.13-.26.189-.568.189-.866 0-.298-.059-.605-.189-.866-.108-.215-.395-.634-.936-.634Zm4.314.634c.108-.215.395-.634.936-.634.54 0 .828.419.936.634.13.26.189.568.189.866 0 .298-.059.605-.189.866-.108.215-.395.634-.936.634-.54 0-.828-.419-.936-.634a1.96 1.96 0 0 1-.189-.866c0-.298.059-.605.189-.866Zm-4.34 7.964a.75.75 0 0 1-1.061-1.06 5.236 5.236 0 0 1 3.73-1.538 5.236 5.236 0 0 1 3.695 1.538.75.75 0 1 1-1.061 1.06 3.736 3.736 0 0 0-2.639-1.098 3.736 3.736 0 0 0-2.664 1.098Z" clip-rule="evenodd" /></svg>''';
  static const String _statsSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M3 6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6Zm4.5 7.5a.75.75 0 0 1 .75.75v2.25a.75.75 0 0 1-1.5 0v-2.25a.75.75 0 0 1 .75-.75Zm3.75-1.5a.75.75 0 0 0-1.5 0v4.5a.75.75 0 0 0 1.5 0V12Zm2.25-3a.75.75 0 0 1 .75.75v6.75a.75.75 0 0 1-1.5 0V9.75A.75.75 0 0 1 13.5 9Zm3.75-1.5a.75.75 0 0 0-1.5 0v9a.75.75 0 0 0 1.5 0v-9Z" clip-rule="evenodd" /></svg>''';

  // Геттер: выбранный таймер для виджета (любой, включая системный)
  TimerItem? get _widgetTimer {
    final timers = _timerService.timers;
    if (timers.isEmpty) return null;
    if (_widgetTimerId != null) {
      try {
        return timers.firstWhere((t) => t.id == _widgetTimerId);
      } catch (_) {}
    }
    // Приоритет: дефолтный таймер (в т.ч. системный — дата начала отношений)
    return _timerService.defaultTimer ?? timers.first;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pair.addListener(_onDataChanged);
    _ws.addListener(_onDataChanged);
    unawaited(_loadNote());
    // Холсты для карточки «Рисунок на столе»: заодно готовятся картинки для
    // виджета, чтобы он не встал пустым сразу после установки.
    unawaited(_loadCanvases());
    _timerService.addListener(_onDataChanged);
    _moodService.addListener(_onDataChanged);
    _mascotService.addListener(_onDataChanged);
    for (final p in _pair.partners) {
      _moodService.listenToPartner(p.uid);
    }
    // Превью «Огонёк пары» показывает реальную серию. Заодно форсим
    // пере-синхронизацию нативного виджета, чтобы на рабочем столе не висело
    // устаревшее значение.
    _mascotService.resyncStreakWidget();
    _loadAllInitialPrefs();
    _panels.addListener(_onPanelsChanged);
    unawaited(_panels.load());

    // Открыты по тапу на парный виджет → сразу разворачиваем его настройки.
    if (widget.openPairEditorOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPairEditor());
    }
  }

  /// Разворачивает карточку «Парный виджет» и прокручивает к ней.
  void _openPairEditor() {
    if (!mounted) return;
    _panels.open(WidgetPanels.pairWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _pairWidgetKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      }
    });
  }

  Future<void> _loadAllInitialPrefs() async {
    final hws = HomeWidgetService.instance;

    final pinSupportedFuture = _checkPinSupportSilent();
    final timerIdFuture = _loadWidgetTimerIdSilent();
    final lockScreenFuture = hws.getLockScreenMoodEnabled();
    final photoGridCount = _ws.myData?.photoGridCount ?? 1;
    final photoDaySaveFuture = hws.getPhotoDaySaveMemory(_pair.pairId);
    final photoDayWidgetsFuture = _loadPhotoDayWidgetsSilent();
    final statsFuture = _loadStatsSilent();
    final daysPhotosFuture = hws.isDaysCounterPhotosEnabled(
      groupId: _pair.pairId,
    );
    final taskPhotosFuture = hws.getPartnerTaskPhotos();

    final results = await Future.wait([
      pinSupportedFuture,
      timerIdFuture,
      lockScreenFuture,
      photoDaySaveFuture,
      photoDayWidgetsFuture,
      statsFuture,
      daysPhotosFuture,
    ]);

    if (!mounted) return;

    final canPin = results[0] as bool;
    final timerId = results[1] as String?;
    final lockEnabled = results[2] as bool;
    final photoDaySave = results[3] as bool;
    final photoDayState = results[4] as Map<String, dynamic>;
    final statsState = results[5] as Map<String, dynamic>;
    final daysPhotos = results[6] as bool;
    final taskPhotos = await taskPhotosFuture;
    if (!mounted) return;

    setState(() {
      _canPinWidgets = canPin;
      _widgetTimerId = timerId;
      _lockScreenMoodEnabled = lockEnabled;
      _savePhotoAsMemory = photoDaySave;
      _daysPhotosEnabled = daysPhotos;
      _partnerTaskPhotos = taskPhotos;
      _photoGridCount = photoGridCount;
      _personalWidgetIds = List<int>.from(photoDayState['personalIds'] ?? []);
      _partnerWidgetIds = List<int>.from(photoDayState['partnerIds'] ?? []);
      _photoDayWidgetNames = Map<int, String>.from(
        photoDayState['names'] ?? {},
      );
      _photoDayWidgetOwnPhotoPaths = Map<int, String?>.from(
        photoDayState['ownPhotoPaths'] ?? {},
      );
      _photoDayWidgetUrls = Map<int, List<String>>.from(
        photoDayState['urls'] ?? {},
      );
      _photoDayWidgetRotationType = Map<int, String>.from(
        photoDayState['rotationType'] ?? {},
      );
      _photoDayWidgetRotationInterval = Map<int, int>.from(
        photoDayState['rotationInterval'] ?? {},
      );
      _selectedPersonalWidgetId = photoDayState['selectedPersonal'] as int?;
      _selectedPartnerWidgetId = photoDayState['selectedPartner'] as int?;
      _memoriesCount = statsState['memoriesCount'] as int?;
      _drawingsCount = statsState['drawingsCount'] as int?;
      _missYouCount = statsState['missYouCount'] as int?;
    });

    _startMissYouListener();

    // Post-setState async operations
    await MoodNotificationService.instance.init();
    if (lockEnabled) await _syncLockScreenMoodWidget(true);
  }

  void _startMissYouListener() {
    _missYouSub?.cancel();
    final groupId = _pair.pairId;
    if (groupId.isEmpty) return;
    // Live-счётчик «Я скучаю» (сумма по паре) из PB — чтения бесплатны.
    _missYouSub = MissYouRepository().watchCounts(groupId).listen((counts) {
      if (mounted) {
        setState(() {
          _missCounts = counts;
          _missYouCount = counts.values.fold<int>(0, (s, v) => s + v);
        });
        unawaited(_sync.miss());
      }
    });
  }

  Future<bool> _checkPinSupportSilent() async {
    // На iPhone программного «закрепить» не существует: виджеты добавляет сама
    // система с рабочего стола. Кнопка «Добавить на рабочий стол» там только
    // вводила в заблуждение — «через приложение не работает, только через
    // рабочий стол». Вместо неё карточка показывает, как добавить вручную
    // (ветка `Platform.isIOS` ниже), но `|| true` перекрывал ответ системы и
    // не давал этой подсказке появиться.
    if (!Platform.isAndroid) return false;
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _loadWidgetTimerIdSilent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_widgetTimerKey);
  }

  Future<Map<String, dynamic>> _loadStatsSilent() async {
    final groupId = _pair.pairId;
    if (groupId.isEmpty) {
      return {'memoriesCount': 0, 'drawingsCount': 0, 'missYouCount': 0};
    }

    final rec = await PbDataService().loadGroupById(groupId);
    final memoriesCount = (rec?.data['memories_count'] as num?)?.toInt() ?? 0;
    final drawingsCount = (rec?.data['drawings_count'] as num?)?.toInt() ?? 0;

    return {
      'memoriesCount': memoriesCount,
      'drawingsCount': drawingsCount,
      'missYouCount': null,
    };
  }

  Future<Map<String, dynamic>> _loadPhotoDayWidgetsSilent() async {
    final hws = HomeWidgetService.instance;
    final allIds = await hws.getPhotoDayWidgetIds();
    final rawPersonalIds = await hws.getSelfPhotoWidgetIds();
    final rawPartnerIds = await hws.getPartnerPhotoWidgetIds();
    final personalIds = <int>[];
    final partnerIds = <int>[];

    for (final id in rawPersonalIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      final isCurrentGroup = _pair.pairId.isEmpty
          ? (widgetGroupId == null ||
                widgetGroupId.isEmpty ||
                widgetGroupId == 'solo')
          : (widgetGroupId == _pair.pairId || widgetGroupId == null);
      if (isCurrentGroup) personalIds.add(id);
    }

    for (final id in rawPartnerIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      final isCurrentGroup = _pair.pairId.isEmpty
          ? (widgetGroupId == null ||
                widgetGroupId.isEmpty ||
                widgetGroupId == 'solo')
          : (widgetGroupId == _pair.pairId || widgetGroupId == null);
      if (isCurrentGroup) partnerIds.add(id);
    }

    final selectedPersonal = PhotoDayWidgetLogic.resolveSelectedWidgetId(
      personalIds,
      _selectedPersonalWidgetId,
    );
    final selectedPartner = PhotoDayWidgetLogic.resolveSelectedWidgetId(
      partnerIds,
      _selectedPartnerWidgetId,
    );

    final widgetNames = <int, String>{};
    final widgetOwnPhotoPaths = <int, String?>{};
    final widgetUrls = <int, List<String>>{};
    final widgetRotationType = <int, String>{};
    final widgetRotationInterval = <int, int>{};

    for (final widgetId in allIds) {
      widgetNames[widgetId] = (await hws.getPhotoDayWidgetName(widgetId)) ?? '';
      final widgetDisplay = await hws.getPhotoDayWidgetDisplay(widgetId);
      final widgetMode = await hws.getPhotoDayWidgetMode(
        widgetId,
        fallbackGroupId: _pair.pairId,
      );
      final preview = await hws.getPhotoDayWidgetPreview(widgetId);
      var customPath = await hws.getPhotoDayWidgetCustomPath(widgetId);
      if (customPath != null &&
          customPath.isNotEmpty &&
          !File(customPath).existsSync()) {
        customPath = null;
      }
      final urls = await hws.getPhotoDayWidgetUrls(widgetId);
      widgetUrls[widgetId] = urls;
      widgetRotationType[widgetId] = await hws.getPhotoDayWidgetRotationType(
        widgetId,
      );
      widgetRotationInterval[widgetId] = await hws
          .getPhotoDayWidgetRotationInterval(widgetId);

      final preferredOwnPath = _resolveWidgetPreviewPath(
        isPartner: widgetDisplay == 'partner',
        widgetUrls: urls,
        widgetPreviewPath: preview['path'],
      );

      final widgetState = PhotoDayWidgetLogic.resolveState(
        selectedWidgetId: widgetId,
        mode: widgetMode,
        display: widgetDisplay,
        widgetPreviewPath: preview['path'],
        widgetCustomPath: customPath,
        fallbackPartnerPhotoPath: _partnerSharedPreviewPath,
      );
      widgetOwnPhotoPaths[widgetId] =
          preferredOwnPath ?? widgetState.ownPhotoPath;
    }

    return {
      'personalIds': personalIds,
      'partnerIds': partnerIds,
      'names': widgetNames,
      'ownPhotoPaths': widgetOwnPhotoPaths,
      'urls': widgetUrls,
      'rotationType': widgetRotationType,
      'rotationInterval': widgetRotationInterval,
      'selectedPersonal': selectedPersonal,
      'selectedPartner': selectedPartner,
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Пользователь вернулся из лончера (после добавления виджета на рабочий
    // стол) — обновляем список виджетов, чтобы новый виджет появился сразу.
    if (state == AppLifecycleState.resumed) {
      _loadPhotoDayWidgets();
      unawaited(_checkPinnedWidgets());
    }
  }

  void _loadStats() {
    _missYouSub?.cancel();
    final groupId = _pair.pairId;
    if (groupId.isEmpty) {
      if (mounted) {
        setState(() {
          _memoriesCount = 0;
          _drawingsCount = 0;
          _missYouCount = 0;
        });
      }
      return;
    }

    // Денормализованные счётчики из group-дока PB.
    PbDataService().loadGroupById(groupId).then((rec) {
      if (rec == null || !mounted) return;
      setState(() {
        _memoriesCount = (rec.data['memories_count'] as num?)?.toInt() ?? 0;
        _drawingsCount = (rec.data['drawings_count'] as num?)?.toInt() ?? 0;
      });
    });

    // Live-счётчик «Я скучаю» (сумма по паре) из PB.
    _missYouSub = MissYouRepository().watchCounts(groupId).listen((counts) {
      if (mounted) {
        setState(
          () => _missYouCount = counts.values.fold<int>(0, (s, v) => s + v),
        );
      }
    });
  }

  Future<void> _loadWidgetTimerId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_widgetTimerKey);
    if (mounted) setState(() => _widgetTimerId = id);
  }

  Future<void> _loadPhotoDayPrefs() async {
    final hws = HomeWidgetService.instance;
    final save = await hws.getPhotoDaySaveMemory(_pair.pairId);
    final tasks = await hws.getPartnerTaskPhotos();

    if (mounted) {
      setState(() {
        _savePhotoAsMemory = save;
        _partnerTaskPhotos = tasks;
      });
    }
  }

  /// Включает снимки из заданий дня в «Фото партнёра» и сразу перерисовывает
  /// виджеты: иначе человек увидел бы их только через 15 минут.
  Future<void> _togglePartnerTaskPhotos(bool value) async {
    setState(() => _partnerTaskPhotos = value);
    final hws = HomeWidgetService.instance;
    await hws.setPartnerTaskPhotos(value);
    if (_pair.pairId.isEmpty) return;
    await hws.refreshPhotoOfDay(_pair.pairId);
    await _ws.syncNow();
  }

  Future<void> _loadPhotoDayWidgets() async {
    final hws = HomeWidgetService.instance;
    final allIds = await hws.getPhotoDayWidgetIds();
    final rawPersonalIds = await hws.getSelfPhotoWidgetIds();
    final rawPartnerIds = await hws.getPartnerPhotoWidgetIds();
    final personalIds = <int>[];
    final partnerIds = <int>[];

    for (final id in rawPersonalIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      final isCurrentGroup = _pair.pairId.isEmpty
          ? (widgetGroupId == null ||
                widgetGroupId.isEmpty ||
                widgetGroupId == 'solo')
          : (widgetGroupId == _pair.pairId || widgetGroupId == null);
      if (isCurrentGroup) personalIds.add(id);
    }

    for (final id in rawPartnerIds) {
      final widgetGroupId = await hws.getPhotoDayWidgetGroupId(id);
      final isCurrentGroup = _pair.pairId.isEmpty
          ? (widgetGroupId == null ||
                widgetGroupId.isEmpty ||
                widgetGroupId == 'solo')
          : (widgetGroupId == _pair.pairId || widgetGroupId == null);
      if (isCurrentGroup) partnerIds.add(id);
    }

    final selectedPersonal = PhotoDayWidgetLogic.resolveSelectedWidgetId(
      personalIds,
      _selectedPersonalWidgetId,
    );
    final selectedPartner = PhotoDayWidgetLogic.resolveSelectedWidgetId(
      partnerIds,
      _selectedPartnerWidgetId,
    );

    final widgetNames = <int, String>{};
    final widgetOwnPhotoPaths = <int, String?>{};
    final widgetUrls = <int, List<String>>{};
    final widgetRotationType = <int, String>{};
    final widgetRotationInterval = <int, int>{};

    for (final widgetId in allIds) {
      widgetNames[widgetId] = (await hws.getPhotoDayWidgetName(widgetId)) ?? '';
      final widgetDisplay = await hws.getPhotoDayWidgetDisplay(widgetId);
      final widgetMode = await hws.getPhotoDayWidgetMode(
        widgetId,
        fallbackGroupId: _pair.pairId,
      );
      final preview = await hws.getPhotoDayWidgetPreview(widgetId);
      var customPath = await hws.getPhotoDayWidgetCustomPath(widgetId);
      if (customPath != null &&
          customPath.isNotEmpty &&
          !File(customPath).existsSync()) {
        customPath = null;
      }
      final urls = await hws.getPhotoDayWidgetUrls(widgetId);
      widgetUrls[widgetId] = urls;
      widgetRotationType[widgetId] = await hws.getPhotoDayWidgetRotationType(
        widgetId,
      );
      widgetRotationInterval[widgetId] = await hws
          .getPhotoDayWidgetRotationInterval(widgetId);

      // Превью: для личного виджета сначала свои URL, для партнёрского —
      // фото партнёра из Firestore, чтобы карточка сразу показывала именно его.
      final preferredOwnPath = _resolveWidgetPreviewPath(
        isPartner: widgetDisplay == 'partner',
        widgetUrls: urls,
        widgetPreviewPath: preview['path'],
      );

      // myPhotoUrl (Firestore) используется только если у виджета есть
      // собственные URL — иначе новый виджет копировал бы превью уже
      // настроенного виджета.
      final widgetState = PhotoDayWidgetLogic.resolveState(
        selectedWidgetId: widgetId,
        mode: widgetMode,
        display: widgetDisplay,
        widgetPreviewPath: preview['path'],
        widgetCustomPath: customPath,
        fallbackPartnerPhotoPath: _partnerSharedPreviewPath,
      );
      widgetOwnPhotoPaths[widgetId] =
          preferredOwnPath ?? widgetState.ownPhotoPath;
    }

    if (!mounted) return;
    setState(() {
      _personalWidgetIds = personalIds;
      _partnerWidgetIds = partnerIds;
      _photoDayWidgetNames = widgetNames;
      _photoDayWidgetOwnPhotoPaths = widgetOwnPhotoPaths;
      _photoDayWidgetUrls = widgetUrls;
      _photoDayWidgetRotationType = widgetRotationType;
      _photoDayWidgetRotationInterval = widgetRotationInterval;
      _selectedPersonalWidgetId = selectedPersonal;
      _selectedPartnerWidgetId = selectedPartner;
    });
  }

  Future<void> _selectPhotoDayWidget(int widgetId) async {
    final hws = HomeWidgetService.instance;
    final kind = await hws.getPhotoDayWidgetKind(widgetId);
    if (!mounted) return;
    setState(() {
      if (kind == 'partner') {
        _selectedPartnerWidgetId = widgetId;
      } else {
        _selectedPersonalWidgetId = widgetId;
      }
    });
  }

  Future<void> _toggleSavePhotoAsMemory(bool value) async {
    final hws = HomeWidgetService.instance;
    await hws.setPhotoDaySaveMemory(_pair.pairId, value);
    if (mounted) setState(() => _savePhotoAsMemory = value);
  }

  String? get _partnerSharedPreviewPath {
    final partnerUrls =
        _ws.firstPartnerData?.photoForPartnerUrls ?? const <String>[];
    if (partnerUrls.isNotEmpty) return partnerUrls.first;

    final singleUrl = _ws.firstPartnerData?.photoForPartnerUrl;
    if (singleUrl != null && singleUrl.isNotEmpty) return singleUrl;

    return null;
  }

  String? _resolveWidgetPreviewPath({
    required bool isPartner,
    required List<String> widgetUrls,
    required String? widgetPreviewPath,
  }) {
    if (isPartner) {
      return _partnerSharedPreviewPath ?? widgetPreviewPath;
    }

    if (widgetUrls.isNotEmpty) return widgetUrls.first;
    return widgetPreviewPath;
  }

  Future<void> _toggleLockScreenMood(bool value) async {
    final hws = HomeWidgetService.instance;
    await hws.setLockScreenMoodEnabled(value);
    if (mounted) setState(() => _lockScreenMoodEnabled = value);
    await _syncLockScreenMoodWidget(value);
  }

  Future<void> _syncLockScreenMoodWidget(bool enabled) async {
    final hws = HomeWidgetService.instance;
    final mns = MoodNotificationService.instance;

    if (!_pair.isPaired) {
      await mns.hide();
      return;
    }

    final today = DateTime.now();
    final myEntries = _moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;
    final partnerUid = _pair.partners.isNotEmpty
        ? _pair.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? _moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;
    final myName = _ws.myData?.displayName ?? '';
    final partnerName = _pair.partnerDisplayName;

    // iOS: HomeWidget (LockScreenMoodWidgetProvider)
    await hws.syncLockScreenMood(
      enabled: enabled,
      moodEmojiAssetPath: myEntry?.imagePath ?? '',
      moodLabel: myEntry?.labelFor(MoodGenders.mine) ?? '',
      userName: myName,
      partnerMoodEmojiAssetPath: partnerEntry?.imagePath ?? '',
      partnerMoodLabel: partnerEntry?.labelFor(_partnerGender) ?? '',
      partnerUserName: partnerName,
    );

    // Android: постоянное уведомление на шторке / экране блокировки
    if (enabled) {
      await mns.show(
        myMood: myEntry?.labelFor(MoodGenders.mine) ?? '',
        myName: myName,
        partnerMood: partnerEntry?.labelFor(_partnerGender) ?? '',
        partnerName: partnerName,
      );
    } else {
      await mns.hide();
    }
  }

  Future<void> _showPhotoDayPhotoSourcePicker(int widgetId) async {
    await _selectPhotoDayWidget(widgetId);
    if (!mounted) return;

    final hws = HomeWidgetService.instance;

    // Каждый виджет редактирует ТОЛЬКО свои фото (per-widgetId).
    // Новый виджет открывается с пустым редактором — фото Firestore других
    // виджетов сюда не подставляются, чтобы каждый экземпляр был уникальным.
    final List<String> initialPaths = await hws.getPhotoDayWidgetUrls(widgetId);

    final initialRotationType = await hws.getPhotoDayWidgetRotationType(
      widgetId,
    );
    final initialRotationInterval = await hws.getPhotoDayWidgetRotationInterval(
      widgetId,
    );

    if (!mounted) return;
    showModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Высоту редактор держит сам перетаскиванием.
      topGap: 0,
      builder: (ctx) => PhotoDayCarouselEditor(
        theme: _t,
        initialPaths: initialPaths,
        initialRotationType: initialRotationType,
        initialRotationInterval: initialRotationInterval,
        onPickFromMemories: _pair.pairId.isNotEmpty
            ? (maxCount) => MemoryPhotoPicker.show(
                ctx,
                groupId: _pair.pairId,
                theme: _t,
                maxCount: maxCount,
                alreadySelected: initialPaths,
              )
            : null,
        onSave:
            ({
              required paths,
              required rotationType,
              required rotationInterval,
            }) async {
              await _saveCarouselForWidget(
                widgetId: widgetId,
                paths: paths,
                rotationType: rotationType,
                rotationInterval: rotationInterval,
              );
            },
      ),
    );
  }

  Future<void> _showPhotoForPartnerSourcePicker() async {
    if (_pair.pairId.isEmpty) return;

    final initialPaths = _ws.myData?.photoForPartnerUrls ?? const <String>[];

    if (!mounted) return;
    showModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      topGap: 0,
      builder: (ctx) => PhotoDayCarouselEditor(
        theme: _t,
        initialPaths: initialPaths,
        initialRotationType: 'none',
        initialRotationInterval: 60,
        onPickFromMemories: (maxCount) => MemoryPhotoPicker.show(
          ctx,
          groupId: _pair.pairId,
          theme: _t,
          maxCount: maxCount,
          alreadySelected: initialPaths,
        ),
        onSave:
            ({
              required paths,
              required rotationType,
              required rotationInterval,
            }) async {
              await _savePhotosForPartner(paths);
            },
      ),
    );
  }

  Future<void> _saveCarouselForWidget({
    required int widgetId,
    required List<String> paths,
    required String rotationType,
    required int rotationInterval,
  }) async {
    final hws = HomeWidgetService.instance;
    final fb = MediaService();

    List<String> uploadedUrls = [];

    // Upload local files, keep remote urls (http/https, gs:// or sb://)
    for (int i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (path.startsWith('http') ||
          path.startsWith('gs://') ||
          path.startsWith('sb://') ||
          path.startsWith('pb://')) {
        // Уже загруженный URL (в т.ч. pb:// — фото «из ленты») — переиспользуем,
        // НЕ пытаемся грузить как локальный файл (File(pb://) не существует).
        uploadedUrls.add(path);
      } else {
        try {
          final uid = PocketBaseService().userId ?? '';
          final ts = DateTime.now().millisecondsSinceEpoch;
          // Когда pairId пустой (соло-режим), используем uid как папку.
          // Путь с пустым сегментом (widget//uid.jpg) сервер не принимает.
          final folder = _pair.pairId.isNotEmpty ? _pair.pairId : uid;

          if (_savePhotoAsMemory && _pair.pairId.isNotEmpty) {
            final destination = 'memories/$folder/photo_day_$ts.jpg';
            final uploadedUrl = await fb.uploadFile(path, destination);
            if (uploadedUrl != null) {
              final me = PbAuthService().currentProfile();
              await MemoryRepository().add(
                groupId: _pair.pairId,
                authorName: (me?['displayName'] as String?) ?? '',
                authorAvatar: (me?['avatarUrl'] as String?) ?? '',
                type: MemoryType.photo,
                imageUrl: uploadedUrl,
                caption: LocaleService.current.setAsPhotoOfDay,
              );
              uploadedUrls.add(uploadedUrl);
            }
          } else {
            final uploadedUrl = await fb.uploadFile(
              path,
              'widget/$folder/${uid}_$ts.jpg',
            );
            if (uploadedUrl != null) uploadedUrls.add(uploadedUrl);
          }
        } catch (e) {
          debugPrint('Failed to upload photo for carousel: $e');
        }
      }
    }

    // Per-widget URL-набор: каждый экземпляр виджета держит СВОИ фото.
    await hws.setPhotoDayWidgetUrls(widgetId, uploadedUrls);

    // Личный фото-виджет — всегда custom (без режима «случайное из воспоминаний»).
    await hws.setPhotoDayWidgetMode(widgetId, 'custom');
    await hws.setPhotoDayWidgetRotationType(widgetId, rotationType);
    await hws.setPhotoDayWidgetRotationInterval(widgetId, rotationInterval);

    // Provide the first local path for backward compatibility preview logic
    if (paths.isNotEmpty) {
      await hws.setPhotoDayWidgetCustomPath(widgetId, paths.first);
    }

    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // Набор уже сохранён — дальше идёт наполнение самого виджета: скачать
    // каждый снимок, ужать, положить в контейнер. Восемь фото по мобильной
    // сети — это минуты, и всё это время лист держал человека спиннером
    // («после добавления фото бесконечная загрузка», 04.09.2026). Ждём
    // недолго и отпускаем: обновление доделает себя само, а следующий заход
    // на экран покажет результат.
    try {
      await hws
          .refreshPhotoOfDay(_pair.pairId, widgetId: widgetId)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      debugPrint('_saveCarouselForWidget: виджет наполнится в фоне');
    }
    await _loadPhotoDayWidgets();
  }

  Future<void> _savePhotosForPartner(List<String> paths) async {
    final fb = MediaService();
    final uid = PocketBaseService().userId ?? '';
    final groupId = _pair.pairId;
    if (uid.isEmpty || groupId.isEmpty) return;

    final uploadedUrls = <String>[];

    for (final path in paths) {
      if (path.startsWith('http') ||
          path.startsWith('gs://') ||
          path.startsWith('sb://') ||
          path.startsWith('pb://')) {
        uploadedUrls.add(path);
        continue;
      }

      try {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final uploadedUrl = await fb.uploadFile(
          path,
          'widget/$groupId/${uid}_partner_$ts.jpg',
        );
        if (uploadedUrl != null) {
          uploadedUrls.add(uploadedUrl);
        }
      } catch (e) {
        debugPrint('Failed to upload photo for partner widget: $e');
      }
    }

    await _ws.updatePhotoForPartnerCarousel(uploadedUrls);
    // Не вызываем refreshPhotoOfDay здесь: виджет «Фото партнёра» на ЭТОМ устройстве
    // показывает фото ПАРТНЁРА, а не мои. Устройство партнёра обновится само через
    // Firestore-листенер, когда получит изменение моего документа.
    await _loadPhotoDayWidgets();
  }

  Future<void> _clearPhotosForPartner() async {
    await _ws.clearPhotoForPartner();
    await _loadPhotoDayWidgets();
    if (!mounted) return;
    _liveSnack(LocaleService.current.photosForPartnerRemoved);
  }

  Future<void> _renamePhotoDayWidget(int widgetId, String nextName) async {
    final trimmedName = nextName.trim();
    await HomeWidgetService.instance.setPhotoDayWidgetName(
      widgetId,
      trimmedName,
    );
    if (!mounted) return;
    setState(() {
      _photoDayWidgetNames = Map<int, String>.from(_photoDayWidgetNames)
        ..[widgetId] = trimmedName;
    });
  }

  void _showPhotoDayWidgetNameEditor(int widgetId, int index) {
    _showTextEditor(
      title: _s.edit,
      hint: _s.name,
      initial: _photoDayWidgetNames[widgetId]?.trim().isNotEmpty == true
          ? _photoDayWidgetNames[widgetId]!
          : _s.widgetSlotTitle(index),
      maxLength: 40,
      onSave: (value) => _renamePhotoDayWidget(widgetId, value),
    );
  }

  Future<void> _selectWidgetTimer(TimerItem timer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_widgetTimerKey, timer.id);
    if (mounted) setState(() => _widgetTimerId = timer.id);
    await HomeWidgetService.instance.syncTimer(timer, groupId: _pair.pairId);
  }

  Future<void> _pinWidget(String qualifiedName, {String? widgetType}) async {
    debugPrint(
      '_pinWidget called: qualifiedName=$qualifiedName, widgetType=$widgetType',
    );
    try {
      final className = qualifiedName.split('.').last;
      debugPrint('_pinWidget: requesting pin for className=$className');

      // Палитру пишем до установки: виджет должен встать на стол уже в цветах
      // активной темы, а не в запасных из хендофа.
      await WidgetThemeSync.save(_cs);

      // Photo day self: works for both solo and paired modes
      if (widgetType == 'photo_day_self') {
        await HomeWidgetService.instance.enqueuePhotoDayWidgetConfig(
          groupId: _pair.pairId,
          // Личный фото-виджет всегда работает с собственными фото пользователя.
          mode: 'custom',
          kind: 'self',
        );
      } else if (widgetType == 'photo_day_partner' && _pair.pairId.isNotEmpty) {
        // Partner photo widget requires a group (partner)
        await HomeWidgetService.instance.enqueuePhotoDayWidgetConfig(
          groupId: _pair.pairId,
          mode: 'random',
          kind: 'partner',
        );
      }

      await _sync.saveBindGroup(widgetType);

      await _pinConfirmation.request(
        ForkIdentity.widgetClass(className),
        () async {
          await HomeWidget.requestPinWidget(
            name: className,
            androidName: className,
            qualifiedAndroidName: ForkIdentity.widgetClass(className),
          );
        },
      );
      if (mounted)
        ForkNotice.info(
          context,
          ruEn(
            'Подтвердите добавление в окне системы',
            'Confirm adding the widget in the system dialog',
          ),
        );
      _pinConfirmationTimer?.cancel();
      _pinConfirmationTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted || timer.tick >= 30) {
          timer.cancel();
          return;
        }
        unawaited(_checkPinnedWidgets());
      });
      // Привязываем виджет к текущей группе и СРАЗУ синхронизируем данные
      // For solo mode, we still sync with empty groupId
      if (widgetType != null) {
        final realType = widgetType.startsWith('photo_day')
            ? 'photo_day'
            : widgetType;
        await HomeWidgetService.instance.bindWidgetToGroup(
          realType,
          _pair.pairId,
        );
        // Немедленно записать актуальные данные в виджет
        await _sync.afterPin(widgetType);
        if (widgetType.startsWith('photo_day')) {
          await _loadPhotoDayWidgets();
        }
      }
    } catch (e, stack) {
      debugPrint('Pin widget failed: $e');
      debugPrint('Pin widget stack: $stack');
      if (mounted) {
        AppSnack.error(context, ForkFailure.of(e).text);
      }
    }
  }

  @override
  void didUpdateWidget(WidgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pairData.pairId != widget.pairData.pairId) {
      // Сменилась группа — загружаем выбор таймера для новой группы
      _loadWidgetTimerId();
      _loadStats();
      _loadPhotoDayPrefs();
      _loadPhotoDayWidgets();
    }
    // Тап по парному виджету, когда вкладка «Виджеты» уже открыта (initState
    // не пересоздаётся) — ловим переход флага false→true.
    if (!oldWidget.openPairEditorOnStart && widget.openPairEditorOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPairEditor());
    }
  }

  @override
  void dispose() {
    _pinConfirmationTimer?.cancel();
    _rewardedAd.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _missYouSub?.cancel();
    _loadPhotoDayDebounce?.cancel();
    _pair.removeListener(_onDataChanged);
    _ws.removeListener(_onDataChanged);
    _timerService.removeListener(_onDataChanged);
    _moodService.removeListener(_onDataChanged);
    _mascotService.removeListener(_onDataChanged);
    _galleryScrollController.dispose();
    _panels.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
    // Обновляем уведомление при изменении настроения
    if (_lockScreenMoodEnabled) {
      _syncLockScreenMoodWidget(true);
    }
    // Если изменились фото-сетки партнёра — обновляем нативный виджет
    final partnerGridUrls = _ws.firstPartnerData?.photoGridUrls ?? [];
    if (partnerGridUrls.isNotEmpty && _pair.pairId.isNotEmpty) {
      HomeWidgetService.instance.refreshPhotoGrid(_pair.pairId);
    }
    if (_pair.pairId.isNotEmpty) {
      _loadPhotoDayDebounce?.cancel();
      _loadPhotoDayDebounce = Timer(
        const Duration(milliseconds: 500),
        _loadPhotoDayWidgets,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _t.bgImageUrl != null
            ? StorageImage(
                imageUrl: _t.bgImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _t.bgGradient,
                  ),
                ),
              ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _galleryScrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    120 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: Column(
                    children: [
                      // ── Виджетов нет у системы, а не у нас ──
                      IosWidgetsUnavailable(cs: _cs),
                      // ── Открытки ──
                      _buildPostcardBanner(),
                      const SizedBox(height: 16),
                      // ── Галерея виджетов рабочего стола ──
                      _buildWidgetGallery(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════════════════════════════════

  /// Шапка каталога.
  ///
  /// Раньше это была строка ростом с четверть экрана: квадрат-иконка,
  /// «Виджеты» кеглем 30 и рядом текстовая кнопка «Сбросить» такого же веса,
  /// как заголовок. Сброс стирает всё содержимое виджета — действие редкое и
  /// необратимое, кричать ему незачем, поэтому оно ушло в иконку с подсказкой.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
      child: Row(
        children: [
          Text(
            _s.widgetsTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
              letterSpacing: -0.8,
              color: _cs.onSurface,
            ),
          ),
          const Spacer(),
          if (_ws.myData != null && !_ws.myData!.isEmpty)
            IconButton(
              onPressed: _confirmClearAll,
              tooltip: _s.resetWidget,
              icon: Icon(
                Icons.restart_alt_rounded,
                size: 22,
                color: _cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET PREVIEW (как выглядит на рабочем столе)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildWidgetPreview() {
    final my = _ws.myData ?? WidgetData(uid: '');
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');

    // Те же источники фото, что и в нативном виджете (_syncToNativeWidget).
    final myPhoto = WidgetService.pairPhotoOfMine(my);
    final partnerPhoto = WidgetService.pairPhotoOfPartner(partner);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.phone_android_rounded, size: 14, color: _t.textMuted),
              const SizedBox(width: 6),
              Text(
                _s.desktopPreview,
                style: AppFonts.onest(
                  size: 12,
                  weight: 600,
                  color: _t.textMuted,
                ),
              ),
            ],
          ),
        ),
        // 1:1 с нативным LoveWidget: две половины (фото или цветная панель),
        // по центру круглый эмодзи, аватар в углу, белый разделитель с сердцем.
        DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 2.0,
              child: Row(
                children: [
                  Expanded(
                    child: PairPreviewHalf(
                      data: my,
                      photoUrl: myPhoto,
                      panelColor: const Color(0xFFFFCDD9),
                      isLeft: true,
                    ),
                  ),
                  // Разделитель с сердцем — те же числа, что в нативной
                  // разметке; см. PairPreviewDivider.
                  const PairPreviewDivider(),
                  Expanded(
                    child: PairPreviewHalf(
                      data: partner,
                      photoUrl: partnerPhoto,
                      panelColor: const Color(0xFFE8DAFF),
                      isLeft: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET GALLERY — все виджеты с превью и кнопкой «Добавить»
  // ════════════════════════════════════════════════════════════════════════════

  /// Разделы каталога подряд, с рекламой между ними.
  ///
  /// Пустой раздел не оставляет после себя дырку: у человека без пары пусты
  /// почти все, и стопка пустых отступов читалась бы как оборванный экран.
  List<Widget> _sections(List<CatalogCard> cards, bool isPaired) {
    final out = <Widget>[];
    void gap() {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
    }

    void section(String key) {
      if (!cards.any((c) => c.section == key)) return;
      gap();
      out.add(_sectionBlock(key, cards));
    }

    section(WidgetPanels.sectionPair);
    section(WidgetPanels.sectionTime);
    section(WidgetPanels.sectionPhotos);
    section(WidgetPanels.sectionMood);
    section(WidgetPanels.sectionNotes);
    return out;
  }

  /// Что показываем в каталоге и в каком разделе.
  ///
  /// Разделов было два — «Что уже есть» и «Новые виджеты», — и делили они
  /// список по возрасту кода: человеку это ничего не говорит, а «Где мы»
  /// вовсе лежал сбоку от обоих. Теперь виджеты разложены по смыслу, а
  /// платные помечены замком внутри своего раздела.
  List<CatalogCard> _catalogCards(bool isPaired, List<Widget> halfTiles) {
    // На iPhone у некупившего Togetherly+ платных карточек не видно вовсе:
    // вести на оплату мимо Apple запрещает 3.1.1.
    final plusShown = PlusService.instance.visible;
    final locked = !PlusService.instance.active;
    final photoOwner = isPaired || _pair.isSolo;
    CatalogCard plus(String section, Widget Function(bool) build) =>
        CatalogCard(section, () => build(locked));
    return [
      // ── Вы вдвоём ──
      if (isPaired) CatalogCard(WidgetPanels.sectionPair, _cardPair),
      if (isPaired && plusShown) plus(WidgetPanels.sectionPair, _cardTogether),
      if (isPaired && plusShown) plus(WidgetPanels.sectionPair, _cardMiss),
      if (isPaired) CatalogCard(WidgetPanels.sectionPair, _cardMap),
      if (isPaired) CatalogCard(WidgetPanels.sectionPair, _cardStats),
      if (isPaired) CatalogCard(WidgetPanels.sectionPair, _cardMascot),
      if (isPaired) CatalogCard(WidgetPanels.sectionPhotos, _cardCanvas),

      // ── Дни и таймеры ──
      if (isPaired) CatalogCard(WidgetPanels.sectionTime, _cardDaysCounter),
      if (halfTiles.isNotEmpty)
        CatalogCard(
          WidgetPanels.sectionTime,
          () => _halfGrid(halfTiles),
          count: halfTiles.length,
        ),
      CatalogCard(WidgetPanels.sectionTime, _cardPetalTimer),
      if (isPaired && plusShown) plus(WidgetPanels.sectionTime, _cardCountdown),
      if (isPaired && plusShown) plus(WidgetPanels.sectionTime, _cardYearRing),
      if (isPaired && plusShown) plus(WidgetPanels.sectionTime, _cardYearGrid),

      // ── Фотографии ──
      if (photoOwner) CatalogCard(WidgetPanels.sectionPhotos, _cardSelfPhoto),
      if (isPaired) CatalogCard(WidgetPanels.sectionPhotos, _cardPartnerPhoto),
      if (isPaired) CatalogCard(WidgetPanels.sectionPhotos, _cardPhotoGrid),

      // ── Настроение ──
      if (isPaired) CatalogCard(WidgetPanels.sectionMood, _cardMood),
      if (isPaired && plusShown) plus(WidgetPanels.sectionMood, _cardMoodTiles),
      if (isPaired)
        CatalogCard(WidgetPanels.sectionMood, _buildLockScreenMoodCard),

      // ── Заметки ──
      if (isPaired && plusShown) plus(WidgetPanels.sectionNotes, _cardNote),
      if (isPaired && plusShown)
        plus(WidgetPanels.sectionNotes, _cardNotePaper),
    ];
  }

  /// Заголовок, подпись и значок раздела.
  (String, String, IconData) _sectionHead(String key) {
    final s = LocaleService.current;
    switch (key) {
      case WidgetPanels.sectionTime:
        return (
          s.widgetSectionTime,
          s.widgetSectionTimeSub,
          Icons.schedule_rounded,
        );
      case WidgetPanels.sectionPhotos:
        return (
          s.widgetSectionPhotos,
          s.widgetSectionPhotosSub,
          Icons.photo_library_rounded,
        );
      case WidgetPanels.sectionMood:
        return (
          s.widgetSectionMood,
          s.widgetSectionMoodSub,
          Icons.mood_rounded,
        );
      case WidgetPanels.sectionNotes:
        return (
          s.widgetSectionNotes,
          s.widgetSectionNotesSub,
          Icons.sticky_note_2_rounded,
        );
      default:
        return (
          s.widgetSectionPair,
          s.widgetSectionPairSub,
          Icons.favorite_rounded,
        );
    }
  }

  /// Раздел каталога: карточки с отступом между ними.
  Widget _sectionBlock(String key, List<CatalogCard> cards) {
    final here = [
      for (final c in cards)
        if (c.section == key) c,
    ];
    if (here.isEmpty) return const SizedBox.shrink();
    final (title, subtitle, icon) = _sectionHead(key);
    return CollapsibleWidgetSection(
      cs: _cs,
      title: title,
      subtitle: subtitle,
      icon: icon,
      expanded: _panels.isExpanded(key),
      onToggle: () => _togglePanel(key),
      count: here.fold(0, (n, c) => n + c.count),
      itemsBuilder: () => [
        for (var i = 0; i < here.length; i++) ...[
          here[i].build(),
          if (i != here.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// Парный виджет: обе половины на одном полотне.
  Widget _cardPair() => KeyedSubtree(
    key: _pairWidgetKey,
    child: _buildGalleryItem(
      title: LocaleService.current.pairWidgetTitle,
      subtitle: LocaleService.current.pairWidgetSubtitle,
      svgString: _heartSvg,
      qualifiedName: 'com.togetherly.love.LoveWidgetProvider',
      preview: _buildWidgetPreview(),
      widgetType: 'pair',
      expandedContent: _buildPairWidgetExpandedContent(),
      isExpanded: _pairWidgetExpanded,
      onToggleExpand: () => _togglePanel(WidgetPanels.pairWidget),
    ),
  );

  /// Дни вместе: главный счётчик пары.
  Widget _cardDaysCounter() => _buildGalleryItem(
    title: LocaleService.current.daysTogetherStat,
    subtitle: LocaleService.current.daysCounterSubtitle,
    svgString: _calendarSvg,
    qualifiedName: 'com.togetherly.love.DaysCounterWidgetProvider',
    preview: DaysCounterPreview(
      t: _t,
      daysPhotosEnabled: _daysPhotosEnabled,
      pair: _pair,
      timerService: _timerService,
      widgetTimer: _widgetTimer,
      ws: _ws,
      userData: widget.userData,
    ),
    widgetType: 'days_counter',
    expandedContent: _buildDaysPhotosCard(),
    isExpanded: _daysCounterExpanded,
    onToggleExpand: () => _togglePanel(WidgetPanels.daysCounter),
  );

  /// Лепестковый таймер: срок кругом из лепестков.
  Widget _cardPetalTimer() => _buildGalleryItem(
    title: LocaleService.current.widgetPetalTimerTitle,
    subtitle: LocaleService.current.widgetPetalTimerSubtitle,
    svgString: _timerSvg,
    qualifiedName: 'com.togetherly.love.PetalTimerWidgetProvider',
    preview: PetalTimerPreview(t: _t, widgetTimer: _widgetTimer),
    widgetType: 'petal_timer',
    expandedContent: _buildTimerSelector(),
    isExpanded: _petalTimerWidgetExpanded,
    onToggleExpand: () => setState(() => _togglePanel(WidgetPanels.petalTimer)),
  );

  /// Настроение обоих.
  Widget _cardMood() => _buildGalleryItem(
    title: LocaleService.current.mood,
    subtitle: LocaleService.current.moodWidgetSubtitle,
    svgString: _moodSvg,
    qualifiedName: 'com.togetherly.love.MoodWidgetProvider',
    preview: MoodPreview(
      t: _t,
      moodService: _moodService,
      pair: _pair,
      ws: _ws,
    ),
    widgetType: 'mood',
  );

  /// Статистика отношений: числа о паре.
  Widget _cardStats() => _buildGalleryItem(
    title: LocaleService.current.relationshipStats,
    subtitle: LocaleService.current.relationshipStatsSubtitle,
    svgString: _statsSvg,
    qualifiedName: 'com.togetherly.love.RelationshipStatsWidgetProvider',
    preview: RelationshipStatsPreview(
      t: _t,
      drawingsCount: _drawingsCount,
      memoriesCount: _memoriesCount,
      missYouCount: _missYouCount,
      pair: _pair,
      timerService: _timerService,
    ),
    widgetType: 'relationship_stats',
  );

  /// Своё фото на рабочем столе.
  Widget _cardSelfPhoto() => _buildGalleryItem(
    title: LocaleService.current.widgetPhotoTitle,
    subtitle: LocaleService.current.widgetPhotoSubtitle,
    svgString: _photoSvg,
    qualifiedName: 'com.togetherly.love.SelfPhotoWidgetProvider',
    widgetType: 'photo_day_self',
    expandedContent: _buildPhotoDayExpandedContent(),
    isExpanded: _photoDayExpanded,
    onToggleExpand: () => _togglePanel(WidgetPanels.photoDay),
  );

  /// Фото, которое поставил партнёр.
  Widget _cardPartnerPhoto() => _buildGalleryItem(
    title: LocaleService.current.widgetModePartner,
    subtitle: LocaleService.current.photoDayPartnerSubtitle,
    svgString: _photoSvg,
    qualifiedName: 'com.togetherly.love.PartnerPhotoWidgetProvider',
    widgetType: 'photo_day_partner',
    expandedContent: _buildPartnerPhotoExpandedContent(),
    isExpanded: _partnerPhotoExpanded,
    onToggleExpand: () =>
        setState(() => _togglePanel(WidgetPanels.partnerPhoto)),
  );

  /// Сетка снимков.
  Widget _cardPhotoGrid() => _buildGalleryItem(
    title: LocaleService.current.photoGridWidget,
    subtitle: LocaleService.current.photoGridWidgetSubtitle,
    svgString: _photoSvg,
    qualifiedName: 'com.togetherly.love.PhotoGridWidgetProvider',
    preview: _buildPhotoGridPreview(),
    widgetType: 'photo_grid',
    expandedContent: _buildPhotoGridExpandedContent(),
    isExpanded: _photoGridExpanded,
    onToggleExpand: () => _togglePanel(WidgetPanels.photoGrid),
  );

  /// Карта на двоих: где каждый и сколько между вами.
  Widget _cardMap() => _buildGalleryItem(
    title: LocaleService.current.liveMapTitle,
    subtitle: LocaleService.current.mapWidgetCatalogSub,
    svgString: _heartSvg,
    qualifiedName:
        'com.togetherly.love.${PairMapWidgetService.androidProviders[MapWidgetSize.m]}',
    widgetType: 'map',
    sizes: [
      for (final (label, hint, kind) in [
        ('2×2', _s.tgSizeHintCompact, MapWidgetSize.s),
        ('4×2', _s.tgSizeHintWide, MapWidgetSize.m),
        ('4×4', _s.tgSizeHintLarge, MapWidgetSize.l),
      ])
        WidgetSizeOption(
          label: label,
          hint: hint,
          qualifiedName:
              'com.togetherly.love.${PairMapWidgetService.androidProviders[kind]}',
          previewBuilder: () => PairMapWidgetPreview(
            key: ValueKey('map-preview-${kind.id}'),
            size: kind,
            theme: _t,
            groupId: _pair.pairId,
            myName: widget.userData.displayName,
            partnerName: _pair.partnerDisplayName,
          ),
        ),
    ],
  );

  /// Виджет «Вместе»: имена, статус и общий срок.
  Widget _cardTogether(bool locked) => _buildGalleryItem(
    title: LocaleService.current.tgTogetherTitle,
    subtitle: LocaleService.current.tgTogetherSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.TogetherWidget4x2Provider',
    widgetType: 'together',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.TogetherWidget2x2Provider',
        previewBuilder: () => TogetherPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          pair: _pair,
          togetherDays: _togetherDays(),
          togetherStart: _togetherStart(),
          size: TogetherCardSize.small,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.TogetherWidget4x2Provider',
        previewBuilder: () => TogetherPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          pair: _pair,
          togetherDays: _togetherDays(),
          togetherStart: _togetherStart(),
          size: TogetherCardSize.medium,
        ),
      ),
      WidgetSizeOption(
        label: '4×4',
        hint: _s.tgSizeHintLarge,
        qualifiedName: 'com.togetherly.love.TogetherWidget4x4Provider',
        previewBuilder: () => TogetherPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          pair: _pair,
          togetherDays: _togetherDays(),
          togetherStart: _togetherStart(),
          size: TogetherCardSize.large,
        ),
      ),
    ],
  );

  /// Перечитать заметку: её правят и отсюда, и прямо с рабочего стола.
  Future<void> _loadNote() async {
    // Пара на первом кадре ещё может не приехать, поэтому есть запасной путь:
    // указатель, который пишет сам сервис виджетов.
    var g = _pair.pairId;
    if (g.isEmpty) {
      g = await HomeWidget.getWidgetData<String>('note_latest_group') ?? '';
    }
    if (g.isEmpty) g = 'solo';
    final text = await HomeWidget.getWidgetData<String>('note_${g}_text') ?? '';
    final author =
        await HomeWidget.getWidgetData<String>('note_${g}_author') ?? '';
    final at = await HomeWidget.getWidgetData<String>('note_${g}_time') ?? '';
    if (!mounted) return;
    setState(() {
      _noteText = text;
      _noteAuthor = author;
      _noteAt = at;
    });
  }

  /// Заметка на двоих, карточкой M3.
  Widget _cardNote(bool locked) => _buildGalleryItem(
    title: _s.tgNoteTitle,
    subtitle: _s.tgNoteSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.NoteWidget4x2Provider',
    widgetType: 'note',
    locked: locked,
    // Вход в саму заметку. До 21.08.2026 её правили ТОЛЬКО тапом по
    // виджету на рабочем столе, и человек, не поставивший виджет (или
    // поставивший его на iPhone, где тап уводит в приложение), спрашивал:
    // «куда написать, чтобы у партнёра было видно запись? никак не могу
    // найти».
    extraAction: _pair.isPaired
        ? (
            label: _s.tgNoteWrite,
            icon: Icons.edit_note_rounded,
            onTap: () async {
              await showNoteEditorSheet(context, groupId: _pair.pairId);
              await _loadNote();
            },
          )
        : null,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.NoteWidget2x2Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
          compact: true,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.NoteWidget4x2Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
        ),
      ),
      WidgetSizeOption(
        label: '4×4',
        hint: _s.tgSizeHintLarge,
        qualifiedName: 'com.togetherly.love.NoteWidget4x4Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
          big: true,
        ),
      ),
    ],
  );

  /// Заметка на двоих, бумажным стикером.
  Widget _cardNotePaper(bool locked) => _buildGalleryItem(
    title: _s.tgNotePaperTitle,
    subtitle: _s.tgNotePaperSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.NoteWidget4x2Provider',
    widgetType: 'note_paper',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.NoteWidget2x2Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
          compact: true,
          paper: true,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.NoteWidget4x2Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
          paper: true,
        ),
      ),
      WidgetSizeOption(
        label: '4×4',
        hint: _s.tgSizeHintLarge,
        qualifiedName: 'com.togetherly.love.NoteWidget4x4Provider',
        previewBuilder: () => CatalogNotePreview(
          noteText: _noteText,
          noteAuthor: _noteAuthor,
          noteAt: _noteAt,
          theme: widget.theme,
          userData: widget.userData,
          big: true,
          paper: true,
        ),
      ),
    ],
  );

  /// Виджет «Скучаю»: нажатие уходит партнёру импульсом.
  Widget _cardMiss(bool locked) => _buildGalleryItem(
    title: LocaleService.current.tgMissTitle,
    subtitle: LocaleService.current.tgMissSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.MissWidget4x2Provider',
    widgetType: 'miss',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.MissWidget2x2Provider',
        previewBuilder: () => MissPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          missCounts: _missCounts,
          pair: _pair,
          size: MissCardSize.small,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.MissWidget4x2Provider',
        previewBuilder: () => MissPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          missCounts: _missCounts,
          pair: _pair,
          size: MissCardSize.medium,
        ),
      ),
      WidgetSizeOption(
        label: '4×1',
        hint: _s.tgSizeHintStrip,
        qualifiedName: 'com.togetherly.love.MissWidget4x1Provider',
        previewBuilder: () => MissPreview(
          cs: _cs,
          ps: _ps,
          userData: widget.userData,
          missCounts: _missCounts,
          pair: _pair,
          size: MissCardSize.strip,
        ),
      ),
    ],
  );

  /// Настроение плитками.
  Widget _cardMoodTiles(bool locked) => _buildGalleryItem(
    title: _s.tgMoodTitle,
    subtitle: _s.tgMoodSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.MoodTilesWidget2x2Provider',
    widgetType: 'mood_tiles',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintToday,
        qualifiedName: 'com.togetherly.love.MoodTilesWidget2x2Provider',
        previewBuilder: () => MoodTiles2x2Preview(
          ps: _ps,
          moodService: _moodService,
          pair: _pair,
          partnerGender: _partnerGender,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWeek,
        qualifiedName: 'com.togetherly.love.MoodTilesWidget4x2Provider',
        previewBuilder: () => MoodTiles4x2Preview(
          ps: _ps,
          moodService: _moodService,
          pair: _pair,
        ),
      ),
    ],
  );

  /// Обратный отсчёт до даты.
  Widget _cardCountdown(bool locked) => _buildGalleryItem(
    title: _s.tgCountdownTitle,
    subtitle: _s.tgCountdownSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.CountdownWidget2x2Provider',
    widgetType: 'countdown',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.CountdownWidget2x2Provider',
        previewBuilder: () =>
            Countdown2x2Preview(ps: _ps, nextEvent: _nextCountdown()),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.CountdownWidget4x2Provider',
        previewBuilder: () => Countdown4x2Preview(
          ps: _ps,
          nextEvent: _nextCountdown(),
          togetherStart: _togetherStart(),
        ),
      ),
    ],
  );

  /// Кольцо года: сколько года прожито вместе.
  Widget _cardYearRing(bool locked) => _buildGalleryItem(
    title: _s.tgRingTitle,
    subtitle: _s.tgRingSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.YearRingWidget4x2Provider',
    widgetType: 'year_ring',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.YearRingWidget2x2Provider',
        previewBuilder: () => _buildYearRing2x2Preview(),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.YearRingWidget4x2Provider',
        previewBuilder: () => _buildYearRing4x2Preview(),
      ),
    ],
  );

  /// Рисунок на столе: общий холст пары, только картинка.
  Widget _cardCanvas() => _buildGalleryItem(
    title: _s.canvasWidgetTitle,
    subtitle: _s.canvasWidgetSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.CanvasWidget2x3Provider',
    widgetType: 'canvas',
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.CanvasWidget2x2Provider',
        previewBuilder: () => CatalogCanvasPreview(
          ps: _ps,
          canvases: _canvases,
          pair: _pair,
          userData: widget.userData,
          aspect: 1,
        ),
      ),
      WidgetSizeOption(
        label: '2×3',
        hint: _s.canvasWidgetSizeTall,
        qualifiedName: 'com.togetherly.love.CanvasWidget2x3Provider',
        previewBuilder: () => CatalogCanvasPreview(
          ps: _ps,
          canvases: _canvases,
          pair: _pair,
          userData: widget.userData,
          aspect: 2 / 3,
        ),
      ),
      WidgetSizeOption(
        label: '4×4',
        hint: _s.tgSizeHintLarge,
        qualifiedName: 'com.togetherly.love.CanvasWidget4x4Provider',
        previewBuilder: () => CatalogCanvasPreview(
          ps: _ps,
          canvases: _canvases,
          pair: _pair,
          userData: widget.userData,
          aspect: 1,
        ),
      ),
    ],
  );

  /// Подтягивает холсты и сразу готовит картинки для виджета.
  Future<void> _loadCanvases() async {
    try {
      final list = await CanvasStorageService.instance.getCanvases(
        widget.userData.uid,
        groupId: _pair.pairId,
      );
      if (!mounted) return;
      setState(() => _canvases = list);
      await _sync.canvas();
    } catch (e) {
      debugPrint('widget_screen: холсты не загрузились — $e');
    }
  }

  /// Маскот на столе: пиксельный персонаж пары в четырёх размерах.
  Widget _cardMascot() => _buildGalleryItem(
    title: _s.mascotWidgetTitle,
    subtitle: _s.mascotWidgetSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.MascotWidget2x2Provider',
    widgetType: 'mascot',
    sizes: [
      WidgetSizeOption(
        label: '4×1',
        hint: _s.tgSizeHintStrip,
        qualifiedName: 'com.togetherly.love.MascotWidget4x1Provider',
        previewBuilder: () => CatalogMascotPreview(
          ps: _ps,
          mascotService: widget.mascotService,
          userData: widget.userData,
          size: MascotPreviewSize.strip,
        ),
      ),
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.MascotWidget2x2Provider',
        previewBuilder: () => CatalogMascotPreview(
          ps: _ps,
          mascotService: widget.mascotService,
          userData: widget.userData,
          size: MascotPreviewSize.small,
        ),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.MascotWidget4x2Provider',
        previewBuilder: () => CatalogMascotPreview(
          ps: _ps,
          mascotService: widget.mascotService,
          userData: widget.userData,
          size: MascotPreviewSize.wide,
        ),
      ),
      WidgetSizeOption(
        label: '4×4',
        hint: _s.tgSizeHintLarge,
        qualifiedName: 'com.togetherly.love.MascotWidget4x4Provider',
        previewBuilder: () => CatalogMascotPreview(
          ps: _ps,
          mascotService: widget.mascotService,
          userData: widget.userData,
          size: MascotPreviewSize.large,
        ),
      ),
    ],
  );

  /// Календарь лет: месяцы точками.
  Widget _cardYearGrid(bool locked) => _buildGalleryItem(
    title: _s.tgGridTitle,
    subtitle: _s.tgGridSubtitle,
    svgString: _heartSvg,
    qualifiedName: 'com.togetherly.love.YearGridWidget4x2Provider',
    widgetType: 'year_grid',
    locked: locked,
    sizes: [
      WidgetSizeOption(
        label: '2×2',
        hint: _s.tgSizeHintCompact,
        qualifiedName: 'com.togetherly.love.YearGridWidget2x2Provider',
        previewBuilder: () =>
            YearGrid2x2Preview(ps: _ps, progress: _yearProgress()),
      ),
      WidgetSizeOption(
        label: '4×2',
        hint: _s.tgSizeHintWide,
        qualifiedName: 'com.togetherly.love.YearGridWidget4x2Provider',
        previewBuilder: () => YearGrid4x2Preview(
          ps: _ps,
          progress: _yearProgress(),
          togetherStart: _togetherStart(),
        ),
      ),
    ],
  );

  Widget _buildWidgetGallery() {
    final isPaired = _pair.isPaired;

    // Простые виджеты — компактными плитками по два в ряд (бенто).
    final halfTiles = <Widget>[
      if (isPaired)
        _buildHalfItem(
          title: LocaleService.current.widgetStreakTitle,
          qualifiedName: 'com.togetherly.love.StreakWidgetProvider',
          widgetType: 'streak',
          preview: _streakCompact(),
        ),
      _buildHalfItem(
        title: LocaleService.current.timerWidgetTitle,
        qualifiedName: 'com.togetherly.love.TimerWidgetProvider',
        widgetType: 'timer',
        preview: _timerCompact(),
        onPreviewTap: _openTimerSelectorSheet,
      ),
    ];

    final cards = _catalogCards(isPaired, halfTiles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 6, bottom: 14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
                  size: 18,
                  color: _cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 11),
              // Заголовок обязан ужиматься: Unbounded 20 плюс системный шрифт
              // 1.3 на экране 320 точек вылезал вправо на 88 пикселей
              // (эмулятор, `wm size 720x1600` + `wm density 360`).
              Expanded(
                child: Text(
                  LocaleService.current.homeScreenWidgets,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontVariations: const [FontVariation('wght', 800)],
                    letterSpacing: -0.5,
                    color: _cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (!isPaired) ...[NotPairedBanner(t: _t), const SizedBox(height: 16)],

        ..._sections(cards, isPaired),
      ],
    );
  }

  // ── Бенто: сетка простых виджетов по два в ряд ──
  Widget _halfGrid(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i + 1 < tiles.length) {
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: tiles[i + 1]),
              ],
            ),
          ),
        );
      } else {
        rows.add(tiles[i]); // нечётный последний — во всю ширину
      }
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// Компактная плитка простого виджета: квадратное превью + имя + круглая
  /// кнопка «добавить на рабочий стол».
  Widget _buildHalfItem({
    required String title,
    required String qualifiedName,
    required String widgetType,
    required Widget preview,
    VoidCallback? onPreviewTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onPreviewTap,
            behavior: HitTestBehavior.opaque,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(height: 128, child: preview),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              height: 1.15,
              color: _cs.onSurface,
            ),
          ),
          if (_canPinWidgets) ...[
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton.icon(
                onPressed: () =>
                    _pinWidget(qualifiedName, widgetType: widgetType),
                icon: const Icon(Icons.add_to_home_screen_rounded, size: 17),
                label: Text(
                  _s.addBtn,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                  ),
                ),
                // Форму и цвет берёт тема: залитая кнопка в приложении —
                // пилюля. Свой прямоугольник с радиусом 14 выбивался из
                // единственного канона на весь проект.
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          ] else if (Platform.isAndroid || Platform.isIOS) ...[
            const SizedBox(height: 9),
            const ForkManualWidgetHint(),
          ],
        ],
      ),
    );
  }

  void _openTimerSelectorSheet() {
    showModalSheet<void>(
      context: context,
      backgroundColor: _cs.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              24,
        ),
        child: SingleChildScrollView(child: _buildTimerSelector()),
      ),
    );
  }

  Widget _halfTileBg(List<Color> colors, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
    child: Center(child: child),
  );

  Widget _streakCompact() => _halfTileBg(
    const [Color(0xFFFFB23E), Color(0xFFFF6A3D)],
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.local_fire_department_rounded,
          color: Colors.white,
          size: 40,
        ),
        Text(
          '${_mascotService.activeStreak}',
          style: const TextStyle(
            fontFamily: 'Unbounded',
            fontSize: 24,
            fontWeight: FontWeight.w800,
            fontVariations: const [FontVariation('wght', 800)],
            color: Colors.white,
            height: 1.05,
          ),
        ),
        Text(
          LocaleService.current.daysInARow,
          style: TextStyle(
            fontFamily: 'Onest',
            fontVariations: const [FontVariation('wght', 400)],
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    ),
  );

  Widget _timerCompact() => _halfTileBg(
    const [Color(0xFF7A5AD0), Color(0xFF9D6FF0)],
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite_rounded, color: Colors.white, size: 34),
        SizedBox(height: 6),
        Text(
          _s.together,
          style: TextStyle(
            fontFamily: 'Onest',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
            color: Colors.white,
          ),
        ),
      ],
    ),
  );

  /// Экран покупки — с карточки виджета, который закрыт замком.
  /// Пол партнёра для подписей его настроения; пусто — общая подпись.
  String get _partnerGender => _ws.firstPartnerData?.gender ?? '';

  void _openPlusScreen() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PlusScreen(scheme: _cs)));

  /// Начало отношений для превью — через общий `couple_days.dart`: более
  /// ранняя из даты таймера и даты коннекта. Иначе превью показывает одно
  /// число, а сам виджет другое.
  DateTime? _togetherStart() => coupleStartDate(
    timerStart:
        (_timerService.defaultTimer ?? _timerService.systemTimer)?.startDate,
    groupStart: _pair.startDate,
    anniversary: _pair.anniversaryDate,
  );

  /// Запись данных в виджеты рабочего стола — по свежему снимку экрана.
  WidgetDataSync get _sync => WidgetDataSync(
    user: widget.userData,
    pair: _pair,
    ws: _ws,
    moods: _moodService,
    timers: _timerService,
    mascot: _mascotService,
    theme: _t,
    ps: _ps,
    widgetTimer: _widgetTimer,
    togetherStart: _togetherStart(),
    memoriesCount: _memoriesCount,
    drawingsCount: _drawingsCount,
    missYouCount: _missYouCount,
    missCounts: _missCounts,
    canvases: _canvases,
  );

  int _togetherDays() =>
      coupleDaysTogether(
        timerStart: (_timerService.defaultTimer ?? _timerService.systemTimer)
            ?.startDate,
        groupStart: _pair.startDate,
        anniversary: _pair.anniversaryDate,
      ) ??
      0;

  /// Какую долю ширины карточки занимает превью размера [label] («2×2»,
  /// «4×2», «4×4»). Ряд на рабочем столе — четыре ячейки, от этого и считаем.
  /// Ширина карточки каталога на экране 360 dp: под неё подобраны кегли и
  /// отступы внутри превью. На узком экране превью ужимается целиком, а не
  /// ломается — см. сборку превью в `_buildGalleryItem`.
  static const double kPreviewDesignWidth = 296;

  double _previewWidthFactor(String? label) {
    final width = int.tryParse((label ?? '').split('×').first) ?? 4;
    return (width / 4).clamp(0.25, 1.0);
  }

  /// Ближайший обратный отсчёт для превью «До встречи».
  TimerItem? _nextCountdown() {
    final now = DateTime.now();
    final upcoming =
        _timerService.timers
            .where((t) => t.isCountdown && t.startDate.isAfter(now))
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Разметка совместного времени для превью «Кольца года» и «Календаря лет».
  /// Тот же расчёт, что уходит в нативные виджеты, поэтому карточка в каталоге
  /// и виджет на столе показывают одно число.
  YearProgress? _yearProgress() {
    final start = _togetherStart();
    return start == null ? null : YearProgress.between(start, DateTime.now());
  }

  /// Превью «Кольцо года»: та же раскладка, что у виджетов на рабочем столе
  /// (`YearRingCard` рисует её в точках среднего виджета iPhone и вписывает в
  /// карточку). До 14.09.2026 превью было своей вёрсткой, и плитки вылезали
  /// за низ карточки, а подписи обрезались многоточием.
  Widget _buildYearRing2x2Preview() => YearRingPreview(
    ps: _ps,
    progress: _yearProgress(),
    memoriesCount: _memoriesCount,
    small: true,
  );

  Widget _buildYearRing4x2Preview() => YearRingPreview(
    ps: _ps,
    progress: _yearProgress(),
    memoriesCount: _memoriesCount,
    small: false,
  );

  Widget _buildGalleryItem({
    required String title,
    required String subtitle,
    required String svgString,
    required String qualifiedName,
    Widget? preview,
    String? widgetType,
    Widget? expandedContent,
    bool isExpanded = false,
    VoidCallback? onToggleExpand,
    List<WidgetSizeOption> sizes = const [],
    bool locked = false,
    ({String label, IconData icon, VoidCallback onTap})? extraAction,
  }) {
    // С выбором размера превью и кнопка работают с выбранным вариантом,
    // без него — со старыми параметрами карточки.
    final hasSizes = sizes.isNotEmpty;
    final choiceKey = widgetType ?? qualifiedName;
    final index = hasSizes
        ? (_panels.sizeOf(choiceKey) ?? 0).clamp(0, sizes.length - 1)
        : 0;
    final chosen = hasSizes ? sizes[index] : null;
    final effectivePreview = chosen != null ? chosen.previewBuilder() : preview;
    final effectiveName = chosen?.qualifiedName ?? qualifiedName;

    return CatalogGlassCard(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок ──
          GestureDetector(
            onTap: onToggleExpand,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.string(
                      svgString,
                      width: 22,
                      height: 22,
                      colorFilter: ColorFilter.mode(
                        _cs.onPrimaryContainer,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          color: _cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontVariations: const [FontVariation('wght', 400)],
                          fontSize: 12.5,
                          color: _cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Чип замка — метка «это по Плюсу» у самой карточки. Стоит
                // рядом с названием, а не поверх превью: смысл витрины в том,
                // чтобы виджет было видно.
                if (locked)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
                    decoration: BoxDecoration(
                      color: _cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 13,
                          color: _cs.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Togetherly+',
                          style: AppFonts.onest(
                            size: 11,
                            weight: 700,
                            color: _cs.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (onToggleExpand != null)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _cs.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          // ── Выбор размера ──
          if (hasSizes) ...[
            const SizedBox(height: 14),
            SizePicker(
              cs: _cs,
              options: sizes,
              selected: index,
              onSelect: (i) => _panels.chooseSize(choiceKey, i),
            ),
          ],
          if (effectivePreview != null) ...[
            const SizedBox(height: 14),
            // Переключение размера меняет пропорции — плавно, а не рывком.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              // Ширину превью держим в пропорции к реальному виджету. Раньше
              // любое превью растягивалось на всю карточку, и квадрат 2×2
              // рисовался шириной в четыре ячейки: огромное пустое поле,
              // аватары-крошки по углам и потерянный текст. Ячеек в ряду
              // четыре, поэтому 2×2 занимает половину, 1×1 — четверть.
              child: LayoutBuilder(
                builder: (context, box) {
                  final factor = _previewWidthFactor(chosen?.label);
                  final target = box.maxWidth * factor;
                  // Ширина превью на экране 360 dp — та, под которую подобраны
                  // кегли внутри. Уже — рисуем в этой ширине и ужимаем целиком,
                  // шире — оставляем как есть, поэтому на привычных экранах
                  // ничего не меняется.
                  final base = kPreviewDesignWidth * factor;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: target,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: math.max(target, base),
                          // Превью — картинка виджета рабочего стола, а не текст
                          // интерфейса: его геометрия задана в точках и
                          // системному шрифту не подчиняется. На эмуляторе с
                          // `font_scale 1.3` подписи внутри распирали превью, и
                          // каталог шёл полосами переполнения — у «Дней вместе»
                          // на 59 пикселей, у настроений на 22, у обратного
                          // отсчёта на 14. Сам виджет на столе рисует
                          // RemoteViews со своими размерами, и крупный шрифт его
                          // не меняет: превью обязано показывать ровно это.
                          child: MediaQuery.withNoTextScaling(
                            child: effectivePreview,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          // ── Кнопка: поставить или открыть покупку ──
          // Под замком кнопка ведёт на экран Плюса, а не в постановку виджета:
          // смотреть можно, ставить нельзя. Тональная заливка, потому что
          // восемь ярких кнопок подряд превращают каталог в рекламный щит.
          if (locked) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.tonalIcon(
                onPressed: _openPlusScreen,
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(
                  _s.plusUnlock,
                  style: AppFonts.onest(size: 14, weight: 700),
                ),
                // Тональная заливка оставлена намеренно (восемь ярких кнопок
                // подряд превращают каталог в рекламный щит), форма — общая.
                style: FilledButton.styleFrom(
                  backgroundColor: _cs.secondaryContainer,
                  foregroundColor: _cs.onSecondaryContainer,
                ),
              ),
            ),
          ] else ...[
            if (extraAction != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.tonalIcon(
                  onPressed: extraAction.onTap,
                  icon: Icon(extraAction.icon, size: 18),
                  label: Text(
                    extraAction.label,
                    style: const TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontVariations: [FontVariation('wght', 700)],
                    ),
                  ),
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ),
            ],
          ],
          if (!locked && _canPinWidgets) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () =>
                    _pinWidget(effectiveName, widgetType: widgetType),
                icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                label: Text(
                  LocaleService.current.addToHomeScreen,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                  ),
                ),
                style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              ),
            ),
          ] else if (!locked && (Platform.isAndroid || Platform.isIOS)) ...[
            const SizedBox(height: 12),
            const ForkManualWidgetHint(),
          ],
          // ── Раскрываемое содержимое ──
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: expandedContent != null && isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Divider(color: _cs.outlineVariant, height: 1),
                      const SizedBox(height: 16),
                      expandedContent,
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Счётчик дней
  // ════════════════════════════════════════════════════════════════════════════

  /// Карточка настройки «Наши фото на виджете Дни вместе» (за коины).
  Widget _buildDaysPhotosCard() {
    final ud = widget.userData;
    final owned = ud.ownsFeature(UserData.featureDaysWidgetPhotos);
    final hasMyPhoto = ud.avatarUrl.isNotEmpty;
    final hasPartnerPhoto = _pair.partnerAvatarUrl.isNotEmpty;
    final bothPhotos = hasMyPhoto && hasPartnerPhoto;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _t.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.face_retouching_natural_rounded,
                color: _t.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  LocaleService.current.ourPhotosInsteadOfDrawing,
                  style: AppFonts.onest(
                    size: 14,
                    weight: 700,
                    color: _t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            LocaleService.current.daysPhotosDescription,
            style: AppFonts.onest(size: 12, color: _t.textSecondary),
          ),
          const SizedBox(height: 14),
          if (!owned)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _daysPhotosBusy ? null : _buyDaysPhotos,
                icon: _daysPhotosBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(
                  LocaleService.current.unlockForCoins(_daysPhotosPrice),
                ),
              ),
            ),
          if (owned) ...[
            // fork: M3
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _daysPhotosEnabled,
              onChanged: (_daysPhotosBusy || !bothPhotos)
                  ? null
                  : _setDaysPhotos,
              title: Text(
                LocaleService.current.showOurPhotos,
                style: AppFonts.onest(
                  size: 13,
                  weight: 600,
                  color: _t.textPrimary,
                ),
              ),
            ),
            if (!bothPhotos)
              Text(
                hasMyPhoto
                    ? LocaleService.current.partnerNoProfilePhoto
                    : LocaleService.current.addYourProfilePhoto,
                style: AppFonts.onest(size: 11, color: Colors.red.shade400),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _buyDaysPhotos() async {
    final ud = widget.userData;
    if (_daysPhotosBusy || ud.ownsFeature(UserData.featureDaysWidgetPhotos)) {
      return;
    }
    if (ud.coins < _daysPhotosPrice) {
      _showDaysPhotosSnack(
        LocaleService.current.notEnoughCoinsNeed(_daysPhotosPrice),
      );
      return;
    }
    setState(() => _daysPhotosBusy = true);
    final ok = await ud.purchaseFeature(UserData.featureDaysWidgetPhotos);
    if (!mounted) return;
    setState(() => _daysPhotosBusy = false);
    if (ok) {
      await _setDaysPhotos(true); // сразу включаем после покупки
      if (mounted) _showDaysPhotosSnack(LocaleService.current.daysPhotosDone);
    } else {
      _showDaysPhotosSnack(LocaleService.current.purchaseFailedTryLater);
    }
  }

  Future<void> _setDaysPhotos(bool enabled) async {
    setState(() {
      _daysPhotosEnabled = enabled;
      _daysPhotosBusy = true;
    });
    // Сервис отвечает тем, что вышло на самом деле: аватарки могут не
    // скачаться, и тогда на рабочем столе остаётся рисунок. Пока ответ никто не
    // смотрел, тумблер обещал фото, которых там нет.
    final applied = await HomeWidgetService.instance.setDaysCounterPhotos(
      groupId: _pair.pairId,
      enabled: enabled,
      myAvatarUrl: widget.userData.avatarUrl,
      partnerAvatarUrl: _pair.partnerAvatarUrl,
    );
    if (!mounted) return;
    setState(() {
      _daysPhotosEnabled = applied;
      _daysPhotosBusy = false;
    });
    if (enabled && !applied) {
      _showDaysPhotosSnack(LocaleService.current.daysPhotosFailed);
    }
  }

  void _showDaysPhotosSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Лепестковый таймер
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // ВЫБОР ТАЙМЕРА ДЛЯ ВИДЖЕТА
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimerSelector() {
    final timers = _timerService.timers;

    if (timers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          LocaleService.current.noTimersAddHint,
          style: AppFonts.onest(size: 12, color: _t.textMuted),
        ),
      );
    }

    final defaultId = (_widgetTimer ?? timers.first).id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleService.current.selectTimerForWidget,
          style: AppFonts.onest(size: 12, weight: 600, color: _t.textSecondary),
        ),
        const SizedBox(height: 10),
        ...timers.map((timer) {
          final isSelected = timer.id == (_widgetTimerId ?? defaultId);
          return GestureDetector(
            onTap: () => _selectWidgetTimer(timer),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF8B5CF6).withOpacity(0.1)
                    : _t.surfaceMuted,
                border: Border.all(
                  color: isSelected ? const Color(0xFF8B5CF6) : _t.divider,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SymbolIcon(
                    SymbolCatalog.nameFromStored(timer.emoji),
                    size: 20,
                    color: isSelected ? _t.primary : _t.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.title,
                          style: AppFonts.onest(
                            size: 13,
                            weight: 600,
                            color: isSelected
                                ? _t.primary
                                : _t.primary.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${timer.daysElapsed.abs()} '
                          '${timer.isCountdown ? LocaleService.current.daysShortLeft : LocaleService.current.daysShortElapsed} • ${timer.formattedStartDate}',
                          style: AppFonts.onest(size: 11, color: _t.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Фото дня
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // НАСТРОЙКИ ФОТО ДНЯ
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoDayExpandedContent() {
    final s = LocaleService.current;
    final hasWidgets = _personalWidgetIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _t.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _t.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.photo_library_rounded, size: 18, color: _t.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _pair.partnerName.isNotEmpty
                      ? LocaleService.current.personalPhotosHelp(
                          _pair.partnerName,
                        )
                      : LocaleService.current.personalPhotosHelpShort,
                  style: AppFonts.onest(
                    size: 11,
                    height: 1.35,
                    color: _t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Раздел строится по номерам виджетов Android; на iPhone их нет, и
        // он врал «Виджет ещё не добавлен» (обращение 284)
        if (!Platform.isIOS) ...[
          const SizedBox(height: 16),
          Text(
            s.widgetInstances,
            style: AppFonts.onest(
              size: 13,
              weight: 700,
              color: _t.primary.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 10),
          _buildPhotoDayWidgetSelector(
            ids: _personalWidgetIds,
            selectedId: _selectedPersonalWidgetId,
            isPartner: false,
          ),
        ],
        if (hasWidgets) ...[
          const SizedBox(height: 12),
          CatalogGlassCard(
            cs: _cs,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.saveToMemoryLane,
                        style: AppFonts.onest(
                          size: 12,
                          weight: 600,
                          color: _t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        LocaleService.current.uploadedPhotosToMemoryLane,
                        style: AppFonts.onest(size: 11, color: _t.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _savePhotoAsMemory,
                  activeColor: _t.primary,
                  onChanged: _toggleSavePhotoAsMemory,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPartnerPhotoExpandedContent() {
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : LocaleService.current.partnerFallback;
    final partnerSharedCount = _ws.firstPartnerData?.sharedPhotoCount ?? 0;
    // Сколько фото показываю партнёру я. Одиночное поле считается за фото,
    // даже когда карусель пуста: у пар, отправлявших фото сразу по обоим
    // направлениям, живо именно оно — и именно его человек не мог убрать.
    final mySharedCount = _ws.myData?.sharedPhotoCount ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _t.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _t.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite_rounded, size: 18, color: _t.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  partnerSharedCount > 0
                      ? LocaleService.current.partnerSharesPhotosHelp(
                          partnerName,
                          partnerSharedCount,
                        )
                      : LocaleService.current.partnerNotSharedHelp(partnerName),
                  style: AppFonts.onest(
                    size: 11,
                    height: 1.35,
                    color: _t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_t.primary.withOpacity(0.92), _t.primary],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ElevatedButton.icon(
              onPressed: _showPhotoForPartnerSourcePicker,
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text(
                LocaleService.current.selectPhotosForPartner,
                style: AppFonts.onest(size: 13, weight: 700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
        if (mySharedCount > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleService.current.youSharePhotosWithPartner(
                      partnerName,
                      mySharedCount,
                    ),
                    style: AppFonts.onest(
                      size: 12,
                      height: 1.3,
                      color: _t.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearPhotosForPartner,
                  style: TextButton.styleFrom(foregroundColor: _t.primary),
                  child: Text(
                    LocaleService.current.stopSharingPhotos,
                    style: AppFonts.onest(size: 12, weight: 700),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        CatalogGlassCard(
          cs: _cs,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trKey('partnerTaskPhotosTitle'),
                      style: AppFonts.onest(
                        size: 12,
                        weight: 600,
                        color: _t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trKey(
                        'partnerTaskPhotosHint',
                      ).replaceAll('{name}', partnerName),
                      style: AppFonts.onest(size: 11, color: _t.textMuted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _partnerTaskPhotos,
                activeColor: _t.primary,
                onChanged: _togglePartnerTaskPhotos,
              ),
            ],
          ),
        ),
        // На iPhone номеров виджетов нет, раздел только путал (обращение 284)
        if (!Platform.isIOS) ...[
          const SizedBox(height: 16),
          Text(
            LocaleService.current.widgetInstances,
            style: AppFonts.onest(
              size: 13,
              weight: 700,
              color: _t.primary.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 10),
          _buildPhotoDayWidgetSelector(
            ids: _partnerWidgetIds,
            selectedId: _selectedPartnerWidgetId,
            isPartner: true,
          ),
        ],
      ],
    );
  }

  Widget _buildPhotoDayWidgetSelector({
    required List<int> ids,
    int? selectedId,
    required bool isPartner,
  }) {
    final s = LocaleService.current;
    if (ids.isEmpty) {
      return CatalogGlassCard(
        cs: _cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.widgetNotAddedYet,
              style: AppFonts.onest(
                size: 13,
                weight: 700,
                color: _t.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.addedWidgetsWillAppearHere,
              style: AppFonts.onest(size: 12, color: _t.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      children: ids.asMap().entries.map((entry) {
        final index = entry.key;
        final widgetId = entry.value;
        final isSelected = widgetId == selectedId;
        final widgetName = _photoDayWidgetNames[widgetId]?.trim();
        final ownPhotoPath = _photoDayWidgetOwnPhotoPaths[widgetId];

        // Счёт фото в виджете
        final int photoCount = isPartner
            ? (_ws.firstPartnerData?.sharedPhotoCount ?? 0)
            : (_photoDayWidgetUrls[widgetId]?.length ?? 0);

        final rotationType = _photoDayWidgetRotationType[widgetId] ?? 'unlock';
        final rotationInterval =
            _photoDayWidgetRotationInterval[widgetId] ?? 60;
        final hasCarousel = photoCount >= 2;
        final String summary = photoCount == 0
            ? (isPartner
                  ? LocaleService.current.noPhotosFromPartner
                  : LocaleService.current.noPhotosAdded)
            : !hasCarousel
            ? LocaleService.current.onePhotoNoCarousel
            : rotationType == 'unlock'
            ? LocaleService.current.photoCountOnUnlock(photoCount)
            : LocaleService.current.photoCountInterval(
                photoCount,
                _intervalLabel(rotationInterval),
              );

        VoidCallback onTapThumb = isPartner
            ? () => _showPartnerWidgetRotationEditor(widgetId)
            : () => _showPhotoDayPhotoSourcePicker(widgetId);

        return GestureDetector(
          onTap: () => _selectPhotoDayWidget(widgetId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? _t.primary.withOpacity(0.08)
                  : _t.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? _t.primary : _t.divider,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onTapThumb,
                  child: Stack(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _t.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? _t.primary.withOpacity(0.35)
                                : _t.divider,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ownPhotoPath != null && ownPhotoPath.isNotEmpty
                            ? (ownPhotoPath.startsWith('http') ||
                                      ownPhotoPath.startsWith('gs://') ||
                                      ownPhotoPath.startsWith('sb://') ||
                                      ownPhotoPath.startsWith('pb://')
                                  ? StorageImage(
                                      imageUrl: ownPhotoPath,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 160,
                                      memCacheHeight: 160,
                                      errorWidget: (_, __, ___) => Icon(
                                        Icons.photo_camera_back_rounded,
                                        color: _t.textMuted,
                                        size: 20,
                                      ),
                                    )
                                  : Image.file(
                                      File(ownPhotoPath),
                                      fit: BoxFit.cover,
                                    ))
                            : Icon(
                                isPartner
                                    ? Icons.favorite_rounded
                                    : Icons.photo_camera_back_rounded,
                                color: _t.textMuted,
                                size: 20,
                              ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _t.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Icon(
                            isPartner
                                ? Icons.access_time_rounded
                                : Icons.edit_rounded,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (photoCount > 1)
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$photoCount',
                              style: AppFonts.onest(
                                size: 9,
                                weight: 700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widgetName?.isNotEmpty == true
                                  ? widgetName!
                                  : s.widgetSlotTitle(index),
                              style: AppFonts.onest(
                                size: 13,
                                weight: 700,
                                color: isSelected ? _t.primary : _t.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () =>
                                _showPhotoDayWidgetNameEditor(widgetId, index),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: isSelected ? _t.primary : _t.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: AppFonts.onest(size: 11, color: _t.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, size: 20, color: _t.primary),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _intervalLabel(int minutes) =>
      LocaleService.current.intervalLabel(minutes);

  Future<void> _showPartnerWidgetRotationEditor(int widgetId) async {
    await _selectPhotoDayWidget(widgetId);
    if (!mounted) return;

    final hws = HomeWidgetService.instance;
    final partnerCount = _ws.firstPartnerData?.sharedPhotoCount ?? 0;
    // Сырое значение бывает `none` (пока снимок был один) — в редакторе это
    // выглядело как «режим не выбран». Показываем тот, который и так работает.
    String rotationType = rotationTypeForEditor(
      await hws.getPhotoDayWidgetRotationType(widgetId),
    );
    int rotationInterval = await hws.getPhotoDayWidgetRotationInterval(
      widgetId,
    );

    if (!mounted) return;
    await showModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void update(VoidCallback fn) => setSheetState(fn);
            final canRotate = partnerCount >= 2;
            return Container(
              decoration: BoxDecoration(
                color: _t.cardSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _t.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    LocaleService.current.partnerPhotoTitle,
                    style: AppFonts.onest(
                      size: 18,
                      weight: 700,
                      color: _t.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canRotate
                        ? LocaleService.current.partnerSharedCountHelp(
                            partnerCount,
                          )
                        : partnerCount == 1
                        ? LocaleService.current.partnerSharedOnePhoto
                        : LocaleService.current.partnerNotSharedYet,
                    style: AppFonts.onest(size: 12, color: _t.textSecondary),
                  ),
                  if (canRotate) ...[
                    const SizedBox(height: 20),
                    Text(
                      LocaleService.current.changePhotosLabel,
                      style: AppFonts.onest(
                        size: 14,
                        weight: 700,
                        color: _t.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: RotationRadio(
                            t: _t,
                            title: LocaleService.current.onUnlockOption,
                            value: 'unlock',
                            groupValue: rotationType,
                            onChanged: (v) =>
                                update(() => rotationType = v ?? 'unlock'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RotationRadio(
                            t: _t,
                            title: LocaleService.current.byTimeOption,
                            value: 'time',
                            groupValue: rotationType,
                            onChanged: (v) =>
                                update(() => rotationType = v ?? 'time'),
                          ),
                        ),
                      ],
                    ),
                    if (rotationType == 'time') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: _t.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: rotationInterval,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                value: 15,
                                child: Text(
                                  LocaleService.current.every15Minutes,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text(
                                  LocaleService.current.every30Minutes,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 60,
                                child: Text(
                                  LocaleService.current.everyHourOption,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 180,
                                child: Text(
                                  LocaleService.current.every3HoursOption,
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                update(() => rotationInterval = v);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        await hws.setPhotoDayWidgetRotationType(
                          widgetId,
                          canRotate ? rotationType : 'none',
                        );
                        await hws.setPhotoDayWidgetRotationInterval(
                          widgetId,
                          rotationInterval,
                        );
                        await hws.refreshPhotoOfDay(
                          _pair.pairId,
                          widgetId: widgetId,
                        );
                        if (mounted) {
                          await _loadPhotoDayWidgets();
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _t.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        LocaleService.current.save,
                        style: AppFonts.onest(size: 15, weight: 700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // КАРТОЧКА: Настроение на экране блокировки
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildLockScreenMoodCard() {
    final s = LocaleService.current;
    final today = DateTime.now();
    final myEntries = _moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;
    final partnerUid = _pair.partners.isNotEmpty
        ? _pair.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? _moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;
    final myName = _ws.myData?.displayName.isNotEmpty == true
        ? _ws.myData!.displayName
        : s.me;
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : s.partner;

    return CatalogGlassCard(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок ──
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _t.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_clock_outlined,
                  size: 20,
                  color: _t.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.lockScreenMood,
                      style: AppFonts.onest(
                        size: 15,
                        weight: 700,
                        color: _t.textPrimary,
                      ),
                    ),
                    Text(
                      s.lockScreenMoodSubtitle,
                      style: AppFonts.onest(size: 11, color: _t.textMuted),
                    ),
                  ],
                ),
              ),
              // Тумблер вкл/выкл
              Switch(
                value: _lockScreenMoodEnabled,
                onChanged: _toggleLockScreenMood,
                activeColor: _t.primary,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Превью: моё и партнёра ──
          AnimatedOpacity(
            opacity: _lockScreenMoodEnabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 250),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _t.primary.withOpacity(0.05),
                    _t.primary.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _t.primary.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: LockMoodHalf(
                      t: _t,
                      entry: myEntry,
                      name: myName,
                      isLeft: true,
                      noMoodLabel: s.lockScreenMoodNoMood,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _t.divider.withOpacity(0),
                          _t.divider,
                          _t.divider.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: LockMoodHalf(
                      t: _t,
                      entry: partnerEntry,
                      name: partnerName,
                      isLeft: false,
                      noMoodLabel: s.lockScreenMoodNoMood,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Подсказка ──
          if (!_lockScreenMoodEnabled) ...[
            const SizedBox(height: 10),
            Text(
              s.lockScreenMoodToggleSub,
              style: AppFonts.onest(size: 11, color: _t.textMuted),
              textAlign: TextAlign.center,
            ),
          ] else if (myEntry == null) ...[
            const SizedBox(height: 10),
            Text(
              s.lockScreenMoodSetHint,
              style: AppFonts.onest(size: 11, color: _t.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Настроение
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Статистика отношений
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // PAIR WIDGET — раскрытые настройки
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPairWidgetExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMyTile(),
        const SizedBox(height: 12),
        _buildPartnerTile(),
        const SizedBox(height: 12),
        _buildSettingsSection(),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MY TILE (editable)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMyTile() {
    final data = _ws.myData ?? WidgetData(uid: '');

    return CatalogGlassCard(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_t.primary, _t.primary.withOpacity(0.7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.myWidget,
                    style: AppFonts.onest(
                      size: 16,
                      weight: 800,
                      color: _t.textPrimary,
                    ),
                  ),
                  Text(
                    _s.tapToEdit,
                    style: AppFonts.onest(size: 11, color: _t.textMuted),
                  ),
                ],
              ),
              const Spacer(),
              EditBadge(t: _t),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты ──
          SlotRow(
            cs: _cs,
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: _s.mood,
            value: data.hasMood ? data.localizedMoodLabel : null,
            valueColor: Colors.white,
            trailing: data.hasMood
                ? ClipOval(
                    child: MoodImage(
                      data.moodEmoji,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
            onTap: () => _showMoodPicker(),
            onClear: data.hasMood
                ? () async {
                    // Единая точка очистки — атомарно во всех источниках.
                    await _moodService.clearMoodForToday();
                  }
                : null,
          ),
          SlotRow(
            cs: _cs,
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: data.hasStatus ? data.status : null,
            onTap: () => _showTextEditor(
              title: _s.status,
              hint: _s.statusHint,
              initial: data.status,
              maxLength: 50,
              onSave: (v) => _ws.updateStatus(v),
            ),
            onClear: data.hasStatus ? () => _ws.clearStatus() : null,
          ),
          SlotRow(
            cs: _cs,
            icon: Icons.mail_outline_rounded,
            iconColor: _t.primary,
            label: _s.message,
            value: data.hasMessage ? '«${data.message}»' : null,
            onTap: () => _showTextEditor(
              title: _s.message,
              hint: _s.messageHint,
              initial: data.message,
              maxLength: 200,
              onSave: (v) => _ws.updateMessage(v),
            ),
            onClear: data.hasMessage ? () => _ws.clearMessage() : null,
          ),
          SlotRow(
            cs: _cs,
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: _s.photo,
            value: data.hasPhoto ? _s.photoUploaded : null,
            // Строка ведёт в выбор нового снимка, а миниатюра — в просмотр
            // нынешнего: своё фото тоже негде было разглядеть.
            trailing: data.hasPhoto
                ? GestureDetector(
                    onTap: () => openWidgetPhotoView(
                      context,
                      imageUrl: data.photoUrl!,
                      authorName: data.displayName.isNotEmpty
                          ? data.displayName
                          : null,
                      updatedAt: data.updatedAt,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: StorageImage(
                        imageUrl: data.photoUrl!,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        progressIndicatorBuilder:
                            (context, url, downloadProgress) {
                              return Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: _t.surfaceMuted,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _t.primary,
                                      value: downloadProgress.progress,
                                    ),
                                  ),
                                ),
                              );
                            },
                        errorWidget: (context, url, error) => Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _t.surfaceMuted,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 18,
                            color: _t.textMuted,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: () => _pickPhoto(),
            onClear: data.hasPhoto ? () => _ws.clearPhoto() : null,
          ),
          SlotRow(
            cs: _cs,
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: _s.music,
            value: data.hasMusic
                ? '${data.musicTitle} — ${data.musicArtist}'
                : null,
            onTap: () => _showMusicEditor(data),
            onClear: data.hasMusic ? () => _ws.clearMusic() : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PARTNER TILE (read-only)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPartnerTile() {
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : _s.partner;
    // Тот же источник, что и у самого виджета на рабочем столе: голый photoUrl
    // пуст у 1877 записей, и строка показывала прочерк там, где на виджете
    // висел кадр из «Фото партнёра» — посмотреть его в приложении было негде.
    final partnerPhoto = WidgetService.pairPhotoOfPartner(partner);
    final hasPartnerPhoto = partnerPhoto.isNotEmpty;

    return CatalogGlassCard(
      cs: _cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _t.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                // pb://-аватар partner'а теперь protected → только через
                // StorageImage (резолвит file-токен). Сырой NetworkImage давал
                // 403 после миграции на PocketBase.
                child: _pair.partnerAvatarUrl.isNotEmpty
                    ? ClipOval(
                        child: StorageImage(
                          imageUrl: _pair.partnerAvatarUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            color: _t.textMuted,
                            size: 22,
                          ),
                        ),
                      )
                    : Icon(Icons.person_rounded, color: _t.textMuted, size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.widgetOfPartner(partnerName),
                    style: AppFonts.onest(
                      size: 16,
                      weight: 800,
                      color: _t.textPrimary,
                    ),
                  ),
                  Text(
                    partner.isEmpty ? _s.emptyYet : _s.updated,
                    style: AppFonts.onest(size: 11, color: _t.textMuted),
                  ),
                ],
              ),
              const Spacer(),
              if (!partner.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: AppFonts.onest(
                          size: 11,
                          weight: 700,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты (read-only) ──
          ReadonlySlot(
            cs: _cs,
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: _s.mood,
            value: partner.hasMood ? partner.localizedMoodLabel : null,
            valueColor: Colors.white,
            trailing: partner.hasMood
                ? ClipOval(
                    child: MoodImage(
                      partner.moodEmoji,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
          ),
          ReadonlySlot(
            cs: _cs,
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: partner.hasStatus ? partner.status : null,
            onOpen: () => _openPartnerText(
              partner,
              partnerName,
              title: _s.status,
              text: partner.status,
            ),
          ),
          ReadonlySlot(
            cs: _cs,
            icon: Icons.mail_outline_rounded,
            iconColor: _t.primary,
            label: _s.message,
            value: partner.hasMessage ? '«${partner.message}»' : null,
            onOpen: () => _openPartnerText(
              partner,
              partnerName,
              title: _s.message,
              text: partner.message,
              quoted: true,
            ),
          ),
          ReadonlySlot(
            cs: _cs,
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: _s.photo,
            value: hasPartnerPhoto ? _s.watchAction : null,
            onOpen: () => openWidgetPhotoView(
              context,
              imageUrl: partnerPhoto,
              authorName: partnerName,
              updatedAt: partner.updatedAt,
            ),
            trailing: hasPartnerPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: StorageImage(
                      imageUrl: partnerPhoto,
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder:
                          (context, url, downloadProgress) {
                            return Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _t.surfaceMuted,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _t.primary,
                                    value: downloadProgress.progress,
                                  ),
                                ),
                              ),
                            );
                          },
                      errorWidget: (context, url, error) => Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _t.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: _t.textMuted,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          ReadonlySlot(
            cs: _cs,
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: _s.music,
            value: partner.hasMusic
                ? '${partner.musicTitle} — ${partner.musicArtist}'
                : null,
            onOpen: () => showWidgetMusicSheet(
              context,
              theme: _t,
              title: partner.musicTitle ?? '',
              artist: partner.musicArtist,
              coverUrl: partner.musicCoverUrl,
              authorUid: partner.uid,
              authorName: partnerName,
              authorAvatarUrl: _pair.partnerAvatarUrl,
              updatedAt: partner.updatedAt,
            ),
          ),
        ],
      ),
    );
  }

  /// Письмо или статус партнёра целиком. Тексты приходят одним листом, разница
  /// только в заголовке.
  void _openPartnerText(
    WidgetData partner,
    String partnerName, {
    required String title,
    required String text,
    bool quoted = false,
  }) {
    showWidgetTextSheet(
      context,
      theme: _t,
      title: title,
      text: text,
      authorUid: partner.uid,
      authorName: partnerName,
      authorAvatarUrl: _pair.partnerAvatarUrl,
      updatedAt: partner.updatedAt,
      quoted: quoted,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SETTINGS SECTION
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: _t.textMuted),
              const SizedBox(width: 6),
              Text(
                _s.widgetSettings,
                style: AppFonts.onest(
                  size: 13,
                  weight: 700,
                  color: _t.textSecondary,
                ),
              ),
            ],
          ),
        ),
        CatalogGlassCard(
          cs: _cs,
          child: Column(
            children: [
              SettingToggle(
                t: _t,
                icon: Icons.photo_library_outlined,
                iconColor: _t.iconPost,
                title: _s.photoToMemoryLane,
                subtitle: _s.autoSavePhotoToMemories,
                value: _ws.autoSendPhotoToMemory,
                onChanged: (v) => _ws.setAutoSendPhotoToMemory(v),
              ),
              SettingDivider(t: _t),
              SettingToggle(
                t: _t,
                icon: Icons.chat_outlined,
                iconColor: _t.primary,
                title: _s.messagestoMemoryLane,
                subtitle: _s.autoSaveMessages,
                value: _ws.autoSendMessageToMemory,
                onChanged: (v) => _ws.setAutoSendMessageToMemory(v),
              ),
              SettingDivider(t: _t),
              SettingToggle(
                t: _t,
                icon: Icons.music_note_outlined,
                iconColor: _t.iconCalendar,
                title: _s.musicToMemoryLane,
                subtitle: _s.autoSaveTracks,
                value: _ws.autoSendMusicToMemory,
                onChanged: (v) => _ws.setAutoSendMusicToMemory(v),
              ),
              SettingDivider(t: _t),
              SettingToggle(
                t: _t,
                icon: Icons.calendar_month_outlined,
                iconColor: _t.iconMood,
                title: _s.moodToCalendar,
                subtitle: _s.autoMarkMoodCalendar,
                value: _ws.autoSendMoodToCalendar,
                onChanged: (v) => _ws.setAutoSendMoodToCalendar(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SLOT ROWS
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // ФОТО-СЕТКА
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoGridPreview() {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: _t.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _t.primary.withOpacity(0.1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: PhotoGridMockup(
            t: _t,
            photoGridCount: _photoGridCount,
            ws: _ws,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoGridExpandedContent() {
    final s = LocaleService.current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Выбор количества фото
        Text(
          s.photoGridCount,
          style: AppFonts.onest(
            size: 13,
            weight: 700,
            color: _t.primary.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1, 2, 4].map((count) {
            final selected = _photoGridCount == count;
            final label = count == 1
                ? '1 ${s.photoGridCountLabel}'
                : count == 2
                ? '2 ${s.photoGridCountLabel}'
                : '4 ${s.photoGridCountLabel}';
            return GestureDetector(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _photoGridCount = count;
                    // Обрезаем список если нужно
                    if (_photoGridPaths.length > count) {
                      _photoGridPaths = _photoGridPaths.sublist(0, count);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? _t.primary.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _t.primary : _t.cardBorder,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppFonts.onest(
                      size: 12,
                      weight: 600,
                      color: selected ? _t.primary : _t.textMuted,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Ячейки фото
        Text(
          s.photoGridSelectPhotos,
          style: AppFonts.onest(
            size: 13,
            weight: 700,
            color: _t.primary.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 10),
        _buildPhotoGridSlots(),
        const SizedBox(height: 16),

        // Кнопка «Обновить виджет»
        if (_isLoadingPhotoGrid)
          Center(child: M3Loading(color: _t.primaryLight))
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _photoGridPaths.isNotEmpty ? _syncPhotoGrid : null,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(LocaleService.current.photoGridSelectPhotos),
              style: ElevatedButton.styleFrom(
                backgroundColor: _t.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoGridSlots() {
    final s = LocaleService.current;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _photoGridCount == 1 ? 1 : 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _photoGridCount,
      itemBuilder: (context, index) {
        final hasPhoto =
            index < _photoGridPaths.length && _photoGridPaths[index].isNotEmpty;
        return GestureDetector(
          onTap: () => _pickPhotoGridSlot(index),
          child: Container(
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasPhoto ? _t.primary.withOpacity(0.3) : _t.cardBorder,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_photoGridPaths[index]),
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                final paths = List<String>.from(
                                  _photoGridPaths,
                                );
                                paths[index] = '';
                                _photoGridPaths = paths;
                              });
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_rounded,
                          size: 28,
                          color: _t.primary.withOpacity(0.4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.photoGridAddPhoto,
                          style: AppFonts.onest(
                            size: 10,
                            color: _t.primary.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickPhotoGridSlot(int index) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhotoSourceSheet(theme: _t),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await safePick(
      () => picker.pickImage(source: source, imageQuality: 85),
    );
    if (picked == null || !mounted) return;

    // Клетка сетки квадратная, поэтому кадр без обрезки теряет края.
    final path =
        await cropPhoto(picked.path, accentColor: _t.primary) ?? picked.path;
    if (!mounted) return;

    setState(() {
      final paths = List<String>.from(_photoGridPaths);
      while (paths.length <= index) {
        paths.add('');
      }
      paths[index] = path;
      _photoGridPaths = paths;
    });
  }

  Future<void> _syncPhotoGrid() async {
    if (_isLoadingPhotoGrid) return;
    setState(() => _isLoadingPhotoGrid = true);
    try {
      final fb = MediaService();
      final uid = PocketBaseService().userId ?? '';
      final groupId = _pair.pairId;

      // 1. Заливаем каждое выбранное фото на сервер
      final List<String> uploadedUrls = [];
      for (int i = 0; i < _photoGridPaths.length; i++) {
        final path = _photoGridPaths[i];
        if (path.isEmpty) continue;
        final ts = DateTime.now().millisecondsSinceEpoch;
        final dest = 'widget/$groupId/${uid}_grid_${i}_$ts.jpg';
        final url = await fb.uploadFile(path, dest);
        if (url != null) uploadedUrls.add(url);
      }

      // 2. Сохраняем МОИ настройки в Firestore (партнёр увидит эти фото)
      await _ws.updatePhotoGrid(_photoGridCount, uploadedUrls);

      // 3. Обновляем виджет рабочего стола (показывает фото ПАРТНЁРА,
      //    т.е. для нас самих здесь ничего не изменится, но инициализируем)
      await HomeWidgetService.instance.refreshPhotoGrid(groupId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocaleService.current.widgetAddedToHome),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('_syncPhotoGrid failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPhotoGrid = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS / BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // POSTCARD BANNER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPostcardBanner() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostcardEditorScreen(
            userData: widget.userData,
            pairData: _pair,
            theme: _t,
            timerStartDate: _widgetTimer?.startDate,
          ),
          settings: const RouteSettings(name: '/postcard_editor'),
        ),
      ),
      // Заливка темы, а НЕ `primaryContainer`. У тем, нарисованных руками,
      // контейнер берётся из `primaryLight` — «чуть тонированного фона», — и на
      // светлой теме баннер сливался со страницей: контраст 1,00 у Фиолетовой,
      // 1,04 у Вишнёвой. Замер по всем 25 палитрам в обеих яркостях: заливка
      // единственная роль, которую видно везде (худший случай 2,05), у
      // контейнера 1,00, у secondaryContainer 1,05, у surfaceContainerHigh 1,01.
      child: Builder(
        builder: (context) {
          final fill = _t.fillColor;
          final ink = AppThemes.onColor(fill, mode: _t.brightness);
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Center(
                    child: Icon(Icons.mail_rounded, color: ink, size: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocaleService.current.createPostcardTitle,
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontVariations: const [FontVariation('wght', 800)],
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        LocaleService.current.createPostcardSubtitle,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontVariations: const [FontVariation('wght', 400)],
                          fontSize: 12.5,
                          color: ink.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Кружок наоборот: чернила заливкой, стрелка цветом баннера. На
                // насыщенном фоне `primary` тонул — он и сам тёмный тон акцента.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: fill,
                    size: 15,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // NOT PAIRED PLACEHOLDER
  // ════════════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════════════
  // DIALOGS / EDITORS
  // ════════════════════════════════════════════════════════════════════════════

  void _showMoodPicker() {
    // Единый общий пикер (с вкладкой «Самочувствие»). setMoodForToday внутри
    // него атомарно обновляет календарь, group memberMoods и widgetData.
    showMoodPicker(
      context: context,
      pairData: _pair,
      moodService: _moodService,
      widgetService: _ws,
      primary: _t.primary,
      navActiveIcon: _t.navActiveIcon,
      // Без этих двух платный пак считался открытым (нет user) и предлагался
      // к выбору там, где его никто не покупал.
      user: widget.userData,
      pairOwned: _mascotService.state.ownedFeatures,
    );
  }

  void _showTextEditor({
    required String title,
    required String hint,
    required String initial,
    required int maxLength,
    required ValueChanged<String> onSave,
  }) {
    showModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WidgetTextEditorSheet(
        theme: _t,
        title: title,
        hint: hint,
        initial: initial,
        maxLength: maxLength,
        onSave: (value) {
          onSave(value);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  /// Живое фото: короткое видео из галереи вместо снимка.
  ///
  /// Кадры из него делает сервер — телефон партнёра не должен разбирать видео
  /// (`MediaMetadataRetriever` тратит 100–200 мс на кадр, и на слабом аппарате
  /// пульс рвётся). Здесь только: взять файл, залить, дождаться раскадровки,
  /// сохранить её для нативной стороны.
  void _liveSnack(String text) {
    if (!mounted) return;
    // Сообщения живого фото написаны парой «русский / английский»; китайский
    // берёт перевод английской половины.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(zhForEnglishIfZh(text))));
  }

  Future<void> _pickLiveVideo() async {
    final ru = LocaleService.instance.isRussian;
    final picker = ImagePicker();
    // Берём `pickMedia`, а не `pickVideo`: гифка в галерее лежит среди
    // фотографий, и выбор видео её просто не показывает — в сборке preview.167
    // живое фото из гифки поставить было нельзя вовсе. Здесь же нельзя задать
    // `maxDuration`, поэтому длину ограничивает сервер (он берёт первые
    // полторы секунды), а вес — проверка ниже.
    final picked = await safePick(() => picker.pickMedia());
    if (picked == null || !mounted) return;

    if (!WidgetAnimService.isSupportedSource(picked.path)) {
      _liveSnack(
        ru
            ? 'Для живого фото нужно видео или гифка'
            : 'A live photo needs a video or a GIF',
      );
      return;
    }

    final file = File(picked.path);
    final size = await file.length();
    if (size > WidgetAnimService.maxSourceBytes) {
      if (!mounted) return;
      final video = WidgetAnimService.isVideoSource(picked.path);
      _liveSnack(
        ru
            ? (video
                  ? 'Видео слишком большое — выберите короче'
                  : 'Гифка слишком большая — выберите полегче')
            : (video
                  ? 'This video is too large — pick a shorter one'
                  : 'This GIF is too large — pick a lighter one'),
      );
      return;
    }

    _showPhotoLoader();
    try {
      // Прежняя раскадровка больше не нужна, а её файл занимает место.
      await WidgetAnimService.instance.clear();
      final uid = PocketBaseService().userId ?? '';
      final ref = await PbMediaService().uploadFile(
        picked.path,
        uid: uid,
        groupId: _pair.pairId,
        kind: 'widget_anim',
      );
      // Ссылка приходит как pb://media/<id>/<file> — нам нужен только id записи.
      final mediaId = (ref ?? '').split('/').length > 3
          ? ref!.split('/')[3]
          : '';
      if (mediaId.isEmpty) throw Exception('upload failed');

      final ready = await WidgetAnimService.instance.fetch(mediaId);
      if (ready == null) throw Exception('prepare failed');

      await HomeWidget.saveWidgetData<String>(
        WidgetAnimService.keyPath,
        ready.path,
      );
      await HomeWidget.saveWidgetData<String>(
        WidgetAnimService.keyManifest,
        ready.manifest,
      );
      await HomeWidget.updateWidget(name: 'LoveWidgetProvider');
      if (mounted) {
        Navigator.of(context).pop();
        _liveSnack(ru ? 'Живое фото в виджете' : 'Live photo is in the widget');
      }
    } catch (e) {
      debugPrint('_pickLiveVideo failed: $e');
      if (mounted) {
        Navigator.of(context).pop();
        _liveSnack(
          ru
              ? 'Не получилось — попробуйте ещё раз'
              : 'Failed — please try again',
        );
      }
    }
  }

  Future<void> _pickPhoto() async {
    final liveActive = await WidgetAnimService.instance.isActive();
    if (!mounted) return;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhotoSourceSheet(theme: _t, liveActive: liveActive),
    );
    if (choice == null || !mounted) return;
    if (choice == kPickLiveVideo) {
      await _pickLiveVideo();
      return;
    }
    if (choice == kDropLiveVideo) {
      await WidgetAnimService.instance.clear();
      if (!mounted) return;
      _liveSnack(ruEn('Живое фото убрано', 'Live photo removed'));
      return;
    }
    final source = choice as ImageSource;

    final picker = ImagePicker();
    final file = await safePick(
      () => picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      ),
    );
    if (file == null || !mounted) return;

    // Кадр на рабочем столе обрезается по ячейке, и решать, что останется в
    // кадре, должен человек, а не BoxFit.cover. Отказ от кроппера означает
    // «оставить как есть», а не отмену постановки фото.
    final photoPath =
        await cropPhoto(file.path, accentColor: _t.primary) ?? file.path;
    if (!mounted) return;

    // Соло-режим: партнёра/воспоминаний нет — старое поведение (только мой виджет).
    if (_pair.pairId.isEmpty) {
      _showPhotoLoader();
      await _ws.updatePhoto(photoPath);
      if (mounted) Navigator.of(context).pop(); // закрываем лоадер
      return;
    }

    // Куда отправить фото — три независимых тумблера (запоминаются).
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final dest = await showModalSheet<PhotoDestinations>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PhotoDestinationSheet(
        theme: _t,
        partnerName: _pair.partnerName,
        initialToPairWidget:
            prefs.getBool('widget_sendPhotoToPairWidget') ?? true,
        initialToPartnerWidget:
            prefs.getBool('widget_sendPhotoToPartnerWidget') ?? true,
        initialToMemories: _ws.autoSendPhotoToMemory,
      ),
    );
    if (dest == null || !mounted) return;
    if (!dest.toPairWidget && !dest.toPartnerWidget && !dest.toMemories) return;

    // Запоминаем выбор для следующего раза.
    await prefs.setBool('widget_sendPhotoToPairWidget', dest.toPairWidget);
    await prefs.setBool(
      'widget_sendPhotoToPartnerWidget',
      dest.toPartnerWidget,
    );
    await _ws.setAutoSendPhotoToMemory(dest.toMemories);

    if (!mounted) return;
    _showPhotoLoader();

    // Один аплоад → раздаём по выбранным направлениям.
    final fb = MediaService();
    final uid = PocketBaseService().userId ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = await fb.uploadFile(
      photoPath,
      'widget/${_pair.pairId}/${uid}_$ts.jpg',
    );

    var memoryFailed = false;
    if (url != null) {
      // 1. Парный виджет (моя половина + у партнёра как фолбэк).
      if (dest.toPairWidget) {
        await _ws.updatePhotoUrl(url);
      }
      // 2. Виджет «Фото партнёра» — то, что осознанно показываем партнёру.
      if (dest.toPartnerWidget) {
        await _ws.updatePhotoForPartnerUrl(url);
        await HomeWidgetService.instance.refreshPhotoOfDay(_pair.pairId);
        await _loadPhotoDayWidgets();
      }
      // 3. Лента воспоминаний.
      if (dest.toMemories) {
        try {
          final me = PbAuthService().currentProfile();
          final created = await MemoryRepository().add(
            groupId: _pair.pairId,
            authorName: (me?['displayName'] as String?) ?? '',
            authorAvatar: (me?['avatarUrl'] as String?) ?? '',
            type: MemoryType.photo,
            imageUrl: url,
            caption: LocaleService.current.widgetPhotoCaption,
          );
          // add() == null → тихий дроп (нет сессии/пустой groupId): фото ушло в
          // виджет, но не в ленту. Раньше это молча терялось — теперь фиксируем и
          // сообщаем пользователю, а не делаем вид, что всё сохранилось.
          if (created == null && mounted) {
            unawaited(
              Sentry.captureMessage(
                'Widget photo: memory add returned null (не добавилось в ленту)',
                withScope: (s) {
                  s.level = SentryLevel.error;
                  s.setExtra('isLoggedIn', PocketBaseService().isLoggedIn);
                  s.setExtra('userIdNull', PocketBaseService().userId == null);
                  s.setExtra('pairIdEmpty', _pair.pairId.isEmpty);
                },
              ),
            );
            memoryFailed = true;
          }
        } catch (e) {
          debugPrint('Widget → Memory (photo) failed: $e');
          memoryFailed = true;
        }
      }
    }

    if (mounted) Navigator.of(context).pop(); // закрываем лоадер
    if (mounted && url == null) {
      // Загрузка не удалась (сеть/сессия). Раньше лоадер просто исчезал без
      // объяснений — теперь честно сообщаем, как на главном экране.
      AppSnack.error(context, LocaleService.current.failedUploadPhoto);
    } else if (mounted && memoryFailed) {
      AppSnack.error(context, LocaleService.current.memoryNotSaved);
    }
  }

  void _showPhotoLoader() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: _t.cardSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3Loading(color: _t.primaryLight),
                const SizedBox(height: 16),
                Text(_s.uploadingPhoto, style: AppFonts.onest(size: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMusicEditor(WidgetData data) {
    showModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MusicEditorSheet(
        theme: _t,
        initialTitle: data.musicTitle ?? '',
        initialArtist: data.musicArtist ?? '',
        initialUrl: data.musicUrl ?? '',
        initialCoverUrl: data.musicCoverUrl ?? '',
        onSave:
            ({
              required String title,
              required String artist,
              String? url,
              String? coverUrl,
            }) {
              _ws.updateMusic(
                title: title,
                artist: artist,
                url: url,
                coverUrl: coverUrl,
              );
              Navigator.pop(ctx);
            },
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await AppDialog.confirm(
      context,
      title: _s.resetWidget,
      message: _s.resetWidgetConfirm,
      confirmLabel: _s.resetBtn,
      destructive: true,
      icon: Icons.restart_alt_rounded,
    );
    if (confirmed) {
      _ws.clearAll();
    }
  }
}
