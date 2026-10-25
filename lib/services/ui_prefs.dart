import '../models/chat_look.dart';
import '../models/chat_reaction.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Лёгкие локальные UI-настройки (без сервера). Единый источник ключей, чтобы
/// главный экран и настройки читали/писали одно и то же.
class UiPrefs {
  UiPrefs._();

  /// Режим боковой кнопки навбара: true = стрелка → (открыть Ленту),
  /// false = плюс + (сразу создать пин). Дефолт — стрелка.
  static const String kHomeSideActionArrow = 'home_side_action_arrow';

  /// Показана ли одноразовая подсказка про удержание боковой кнопки.
  static const String kSideActionHintSeen = 'side_action_hint_seen';

  /// Настройки кисти холста: сглаживание, ровные фигуры, симметрия. Живут
  /// на устройстве — это привычка руки, а не общее имущество пары.
  static const String kBrushSmoothing = 'draw_brush_smoothing';

  /// Состав и порядок панели быстрого доступа холста.
  static const String kDrawQuickTools = 'draw_quick_tools';

  /// Подсказку про выделение показываем один раз: дальше она только мешает.
  static const String kSelectToolHintSeen = 'draw_select_hint_seen';

  /// Каким видом открывать экран настроений: сеткой или сосудом.
  static const String kMoodVesselView = 'mood_vessel_view';
  static const String kBrushQuickShapes = 'draw_brush_quick_shapes';
  static const String kBrushSymmetry = 'draw_brush_symmetry';
  static const String kBrushSymmetrySectors = 'draw_brush_symmetry_sectors';

  /// Кисть холста, режим и толщина ластика (20.10.2026). Тоже привычка руки.
  static const String kDrawBrush = 'draw_brush_kind';
  static const String kEraserMode = 'draw_eraser_mode';
  static const String kEraserWidth = 'draw_eraser_width';

  /// Кнопка справа от поля чата: снимает фигурку вместо записи голоса.
  /// Живёт на устройстве — это привычка, а не решение пары.
  static const String kChatNoteMode = 'chat_note_mode';

  /// Последняя выбранная форма фигурки.
  static const String kChatNoteShape = 'chat_note_shape';

  static Future<bool> chatNoteMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kChatNoteMode) ?? false;
  }

  static Future<void> setChatNoteMode(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kChatNoteMode, on);
  }

  static Future<String> chatNoteShape() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kChatNoteShape) ?? '';
  }

  static Future<void> setChatNoteShape(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kChatNoteShape, id);
  }

  static Future<bool> sideActionIsArrow() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kHomeSideActionArrow) ?? true;
  }

  static Future<void> setSideActionIsArrow(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kHomeSideActionArrow, value);
  }

  static Future<bool> sideActionHintSeen() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kSideActionHintSeen) ?? false;
  }

  static Future<void> markSideActionHintSeen() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kSideActionHintSeen, true);
  }

  /// Показан ли экран приглашения партнёра после регистрации. Флаг локальный
  /// намеренно: экран нужен один раз новичку, а не каждому, кто когда-то
  /// расстался и остался без пары.
  static const String kInviteScreenShown = 'invite_screen_shown';

  static Future<bool> inviteScreenShown() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kInviteScreenShown) ?? false;
  }

  static Future<void> markInviteScreenShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kInviteScreenShown, true);
  }

  /// Карточка первых действий закрыта крестиком.
  static const String kOnboardingDismissed = 'onboarding_card_dismissed';

  static Future<bool> onboardingDismissed() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kOnboardingDismissed) ?? false;
  }

  static Future<void> dismissOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kOnboardingDismissed, true);
  }

  /// Виджет добавлен на рабочий стол. Считаем по факту: успешное добавление из
  /// каталога или ответ системы, что наш виджет стоит на экране
  /// (`HomeWidgetService.anyWidgetOnScreen`). Записи `widget_data` заводятся
  /// при любой синхронизации и о рабочем столе ничего не говорят.
  static const String kWidgetPinned = 'widget_pinned_once';

  static Future<bool> widgetPinned() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(kWidgetPinned) ?? false;
  }

  static Future<void> markWidgetPinned() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kWidgetPinned, true);
  }

  /// Вид чата (`ChatLook`): `cozy` — наш (кривые углы, хвостики, наклон,
  /// мордочки), `material` — обычные пузыри, `sticker` — наклейка, `pixel` —
  /// пиксель. Хранится локально:
  /// это дело вкуса каждого, а не пары.
  /// Реакция двойного касания в чате (эмодзи). Своя у каждого.
  static const String kQuickReaction = 'chat_quick_reaction';

  static Future<String> quickReaction() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(kQuickReaction) ?? '';
    return v.isEmpty ? kDefaultQuickReaction : v;
  }

  static Future<void> setQuickReaction(String emoji) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kQuickReaction, emoji);
  }

  static const String kChatLook = 'chat_look';

  static Future<ChatLook> chatLook() async {
    final p = await SharedPreferences.getInstance();
    return chatLookFromName(p.getString(kChatLook));
  }

  static Future<void> setChatLook(ChatLook look) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kChatLook, look.name);
  }

  /// Узор фона чата (имя значения `ChatBackground`). По умолчанию «точки»:
  /// самый нейтральный из семи — работает с любой из двадцати палитр и не
  /// спорит с пузырями. Хранится локально, как и вид пузырей: это вкус
  /// каждого, а общий фон-картинка пары живёт отдельно в `groups`.
  static const String kChatBackground = 'chat_background_pattern';

  static Future<String> chatBackground() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kChatBackground) ?? 'dots';
  }

  static Future<void> setChatBackground(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kChatBackground, name);
  }

  /// Когда в последний раз отправляли «Скучаю» с карточки затихшего партнёра
  /// (epoch ms). Ограничивает подсказку одним разом в сутки.
  static const String kQuietNudgeAt = 'quiet_partner_nudge_at';

  static Future<int?> quietNudgeAt() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getInt(kQuietNudgeAt) ?? 0;
    return v > 0 ? v : null;
  }

  static Future<void> markQuietNudgeSent(int atMs) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(kQuietNudgeAt, atMs);
  }

  /// Одноразовые подсказки о новых функциях.
  ///
  /// Ключ у каждой свой (`snap_hold`, `miss_screen`, `side_action`), очередь
  /// показа держит [HintQueue]. Отметка ставится в момент показа, а не по
  /// кнопке «Понятно»: закрытый тапом мимо пузырь возвращаться не должен.
  /// У подсказки про боковую кнопку ключ старше самой очереди, и менять его
  /// нельзя: те, кто её уже видел, получили бы её заново.
  static String hintKey(String name) =>
      name == 'side_action' ? kSideActionHintSeen : 'hint_${name}_seen';

  static Future<bool> hintSeen(String name) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(hintKey(name)) ?? false;
  }

  static Future<void> markHintSeen(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(hintKey(name), true);
  }

  /// Свёрнутые секции экранов — ключи вида `profile:pair`, `settings:about`.
  ///
  /// Храним именно СВЁРНУТЫЕ, а не развёрнутые: раскрытая секция — состояние по
  /// умолчанию, и человек, который ничего не сворачивал, не должен получить
  /// схлопнутый экран из-за пустого списка.
  ///
  /// Решение переживает выход с экрана: свернувший «Отношения» один раз хочет
  /// видеть их свёрнутыми и завтра, а не сворачивать заново на каждый заход.
  static const String kCollapsedSections = 'collapsed_sections';

  static Future<Set<String>> collapsedSections() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(kCollapsedSections) ?? const <String>[]).toSet();
  }

  static Future<void> setSectionCollapsed(String key, bool collapsed) async {
    final p = await SharedPreferences.getInstance();
    final saved = (p.getStringList(kCollapsedSections) ?? const <String>[])
        .toSet();
    if (collapsed) {
      saved.add(key);
    } else {
      saved.remove(key);
    }
    await p.setStringList(kCollapsedSections, saved.toList());
  }

  // ── «Умение любить»: карточка на главной ──────────────────────────────────

  static const _loveDismissedKey = 'love_test_prompt_dismissed';

  /// Карточку показываем один раз: прошли или закрыли — она больше не
  /// появится. Флаг локальный, у каждого свой: тест проходят по отдельности.
  static Future<bool> loveTestPromptDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loveDismissedKey) ?? false;
  }

  static Future<void> dismissLoveTestPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loveDismissedKey, true);
  }

  // ── Лента воспоминаний ──
  /// Чем упорядочена лента: `eventDate` (когда это случилось) или `addedAt`
  /// (когда занесли). Выбор человека, а не состояние экрана.
  static const String kMemorySort = 'memory_sort';

  static Future<String?> memorySort() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kMemorySort);
  }

  static Future<void> setMemorySort(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kMemorySort, value);
  }
}
