import 'dart:async';
import '../utils/safe_launch.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/symbol_catalog.dart';
import '../models/wish.dart';
import '../models/wish_category.dart';
import '../models/wish_comment.dart';
import '../models/wish_order.dart';
import '../models/wish_reservation.dart';
import '../dict_strings.dart';
import '../services/locale_service.dart';
import '../services/plus_service.dart';
import '../services/wish_repository.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/common/app_dialog.dart';
import '../widgets/common/stable_stream_builder.dart';
import '../widgets/storage_image.dart';
import '../fork/wishes/wish_memory.dart';
import '../fork/wishes/wish_place_picker.dart';
import '../fork/wishes/wish_places.dart';
import '../fork/wishes/wish_reminder_plan.dart';
import '../fork/wishes/wish_reminder_settings.dart';
import '../fork/wishes/wish_reminders.dart';
import '../fork/wishes/wish_wall.dart';
import '../models/memory.dart';
import '../services/memory_repository.dart';
import '../widgets/wishes/wish_category_sheet.dart';
import '../widgets/wishes/wish_comments_sheet.dart';
import '../widgets/wishes/wish_details_sheet.dart';
import '../widgets/wishes/wish_due_picker.dart';
import '../widgets/wishes/wish_form_sheet.dart';
import 'plus_screen.dart';

/// «Хочу с тобой» — общий список желаний пары.
///
/// Две вкладки вместо одного списка с разделами: рабочая часть не растёт от
/// архива, а отметка уезжает во вторую вкладку и подтверждается снекбаром с
/// отменой. Записи общие, поэтому отметить сбывшимся может любой из двоих;
/// править и удалять желание оставлено автору.
class WishesScreen extends StatefulWidget {
  const WishesScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.myUid,
    required this.myName,
    required this.partnerUid,
    required this.partnerName,
    this.myAvatarUrl,
    this.partnerAvatarUrl,
    this.openFulfilled = false,
    this.sharedUrl = '',
    this.onOpenMemory,
  });

  final AppTheme theme;
  final String groupId;
  final String myUid;
  final String myName;
  final String partnerUid;
  final String partnerName;

  /// Аватары обоих: подпись автора рисуется живым лицом, а не буквой.
  final String? myAvatarUrl;
  final String? partnerAvatarUrl;

  /// Открыть сразу архив — из строки «12 уже сбылось» на главной.
  final bool openFulfilled;

  /// Ссылка из «Поделиться»: экран открывается с готовой формой вещи.
  final String sharedUrl;

  /// Открыть воспоминание, привязанное к сбывшемуся (docs/WISHLIST.md).
  /// Null — экран открыт без ленты под рукой: кнопки «Открыть» нет.
  final void Function(String memoryId)? onOpenMemory;

  @override
  State<WishesScreen> createState() => _WishesScreenState();
}

class _WishesScreenState extends State<WishesScreen> {
  final WishRepository _repo = WishRepository.instance;
  late bool _fulfilledTab = widget.openFulfilled;

  /// Свои категории пары. Держим их в состоянии экрана, а не тянем в каждый
  /// лист заново: список короткий, а лист открывается поверх и своего потока
  /// уже не получит.
  List<WishKind> _custom = const [];
  StreamSubscription<List<WishKind>>? _customSub;

  /// Вещи, которые я взял на себя. Список приходит только свой: у коллекции
  /// правило чтения `uid = auth.id`, автору сюрприз не виден вовсе.
  /// Свои «Дарю» по id желания.
  Map<String, WishReservation> _reservations = const {};
  Set<String> get _reserved => _reservations.keys.toSet();

  /// Подпись списка, по которой в последний раз пересчитали напоминания.
  String _remindersSig = '';

  /// Сколько комментариев у желаний — цифра на карточке.
  Map<String, int> _commentCounts = const {};
  StreamSubscription<List<WishComment>>? _commentsSub;

  /// Воспоминания пары: выбор для сбывшегося и картинки стены.
  Map<String, Memory> _memories = const {};
  StreamSubscription<List<Memory>>? _memoriesSub;

  /// Места после перетаскивания, пока запись не вернулась из кэша: без них
  /// карточка на миг прыгала бы обратно.
  final Map<String, double> _posOverride = {};

  ColorScheme get _cs => Theme.of(context).colorScheme;
  bool get _ru => LocaleService.instance.isRussian;

  String _tr(String ru, String en) => ruEn(ru, en);

  @override
  void initState() {
    super.initState();
    _customSub = _repo.watchCategories(widget.groupId).listen((list) {
      if (mounted) setState(() => _custom = list);
    });
    _memoriesSub = MemoryRepository.instance.watch(widget.groupId).listen((
      list,
    ) {
      if (mounted) setState(() => _memories = {for (final m in list) m.id: m});
    });
    _commentsSub = _repo.watchComments(widget.groupId).listen((list) {
      if (mounted) setState(() => _commentCounts = wishCommentCounts(list));
    });
    _loadReservations();
    if (widget.sharedUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addShared());
    }
  }

  /// Форма вещи с подставленной ссылкой — сразу после открытия экрана.
  Future<void> _addShared() async {
    final draft = await _openForm(initialUrl: widget.sharedUrl);
    if (draft == null) return;
    await _repo.add(
      groupId: widget.groupId,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
      due: draft.due,
      place: draft.place,
    );
  }

  Future<void> _loadReservations() async {
    final list = await _repo.loadReservations(widget.groupId);
    if (!mounted) return;
    setState(() {
      _reservations = {
        for (final r in list)
          if (r.wishId.isNotEmpty) r.wishId: r,
      };
    });
  }

  /// «Дарю» и обратно. Состояние правим на месте: список свой, ждать ответа
  /// сервера ради переключения одной иконки незачем.
  Future<void> _toggleReserve(Wish wish) async {
    final taken = _reservations[wish.id];
    if (taken != null) {
      await _reserveSheet(wish, taken);
      return;
    }
    final res = await _repo.reserve(groupId: widget.groupId, wishId: wish.id);
    if (res == null || !mounted) return;
    setState(() => _reservations = {..._reservations, wish.id: res});
    WishReminders.instance.schedule();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _cs.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Text(
          _tr(
            'Дарите вы — партнёр не узнает',
            "You're gifting it — your partner won't know",
          ),
          style: AppFonts.onest(size: 14, color: _cs.onInverseSurface),
        ),
        action: SnackBarAction(
          label: _tr('СРОК', 'DEADLINE'),
          textColor: _cs.inversePrimary,
          onPressed: () => _pickReserveUntil(res),
        ),
      ),
    );
  }

  /// Срок «Дарю» (docs/WISHLIST.md): напомнит только дарящему.
  Future<void> _pickReserveUntil(WishReservation res) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = res.until;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(today)
          ? today.add(const Duration(days: 7))
          : current,
      firstDate: today,
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: _tr('Подарить до', 'Gift by'),
      builder: (ctx, child) =>
          Theme(data: ProfileTheme.data(_cs), child: child!),
    );
    if (picked == null || !mounted) return;
    final next = await _repo.setReserveUntil(
      groupId: widget.groupId,
      res: res,
      until: picked,
    );
    if (!mounted) return;
    setState(() => _reservations = {..._reservations, next.wishId: next});
    WishReminders.instance.schedule();
  }

  /// Взятая вещь: срок или «передумал».
  Future<void> _reserveSheet(Wish wish, WishReservation res) async {
    final s = LocaleService.current;
    final until = res.until;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cs.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                wish.title,
                style: AppFonts.onest(size: 16, weight: 700),
              ),
              subtitle: Text(
                _tr(
                  'Дарите вы — партнёр не знает',
                  "You're gifting it — your partner doesn't know",
                ),
              ),
            ),
            ListTile(
              key: const Key('wish-reserve-until'),
              leading: Icon(
                Icons.event_rounded,
                color: res.overdue(DateTime.now()) ? _cs.error : _cs.primary,
              ),
              title: Text(
                until == null
                    ? _tr('Поставить срок', 'Set a deadline')
                    : '${_tr('Срок', 'Deadline')}: ${s.dayLogDate(until)}',
              ),
              onTap: () => Navigator.of(ctx).pop('until'),
            ),
            if (until != null)
              ListTile(
                leading: const Icon(Icons.event_busy_rounded),
                title: Text(_tr('Без срока', 'No deadline')),
                onTap: () => Navigator.of(ctx).pop('clear'),
              ),
            ListTile(
              key: const Key('wish-reserve-release'),
              leading: const Icon(Icons.undo_rounded),
              title: Text(_tr('Передумал — отпустить', 'Changed my mind')),
              onTap: () => Navigator.of(ctx).pop('release'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'until':
        await _pickReserveUntil(res);
      case 'clear':
        final next = await _repo.setReserveUntil(
          groupId: widget.groupId,
          res: res,
          until: null,
        );
        if (!mounted) return;
        setState(() => _reservations = {..._reservations, next.wishId: next});
        WishReminders.instance.schedule();
      case 'release':
        setState(() => _reservations = {..._reservations}..remove(wish.id));
        await _repo.release(res.id);
        WishReminders.instance.schedule();
    }
  }

  /// Привязать сбывшееся к воспоминанию — сразу после отметки или позже.
  Future<void> _linkMemory(Wish wish) async {
    final id = await pickWishMemory(
      context,
      wish: wish,
      memories: _memories.values.toList(),
    );
    if (id == null || !mounted) return;
    await _repo.linkMemory(groupId: widget.groupId, wish: wish, memoryId: id);
  }

  void _openWall(List<Wish> fulfilled) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: ProfileTheme.data(_cs),
          child: WishWallScreen(
            fulfilled: fulfilled,
            memories: _memories,
            onOpen: widget.onOpenMemory == null
                ? null
                : (w) {
                    if (w.memoryId.isNotEmpty &&
                        _memories.containsKey(w.memoryId)) {
                      widget.onOpenMemory!(w.memoryId);
                    }
                  },
          ),
        ),
        settings: const RouteSettings(name: '/wishes/wall'),
      ),
    );
  }

  /// Попросили другое желание недели: это до конца недели не выпадает.
  Future<void> _anotherWeekly(Wish wish) => _repo.skipWeek(
    groupId: widget.groupId,
    wish: wish,
    weekKey: isoWeekKey(DateTime.now()),
  );

  void _openReminderSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: ProfileTheme.data(_cs),
          child: const WishReminderSettingsScreen(),
        ),
        settings: const RouteSettings(name: '/wishes/reminders'),
      ),
    );
  }

  /// Список поменялся по существу — пересчитать напоминания.
  void _maybeReschedule(List<Wish> all) {
    final sig = [
      for (final w in all)
        '${w.id}|${w.done}|${w.due.encode()}|${w.skip}|${w.isItem}|${w.title}'
            '|${w.place?.encode()}',
    ].join(';');
    if (sig == _remindersSig) return;
    _remindersSig = sig;
    WishReminders.instance.schedule();
    WishPlaces.instance.invalidate();
  }

  @override
  void dispose() {
    _customSub?.cancel();
    _commentsSub?.cancel();
    _memoriesSub?.cancel();
    super.dispose();
  }

  /// Имя того, кто завёл желание. Чужой uid без имени бывает у мигрированных
  /// пар — тогда лучше промолчать, чем показать кусок идентификатора.
  String _nameOf(String uid) {
    if (uid == widget.myUid) return widget.myName;
    if (uid == widget.partnerUid) return widget.partnerName;
    return '';
  }

  String? _avatarOf(String uid) {
    if (uid == widget.myUid) return widget.myAvatarUrl;
    if (uid == widget.partnerUid) return widget.partnerAvatarUrl;
    return null;
  }

  // ── Действия ──────────────────────────────────────────────────────────────

  Future<void> _add() async {
    final draft = await _openForm();
    if (draft == null) return;
    await _repo.add(
      groupId: widget.groupId,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
      due: draft.due,
      place: draft.place,
    );
  }

  Future<void> _edit(Wish wish) async {
    final draft = await _openForm(existing: wish);
    if (draft == null) return;
    await _repo.edit(
      noPlace: draft.place == null,
      groupId: widget.groupId,
      wish: wish,
      title: draft.title,
      kind: draft.kind,
      note: draft.note,
      isItem: draft.isItem,
      price: draft.price,
      currency: draft.currency,
      url: draft.url,
      image: draft.image,
      shop: draft.shop,
      due: draft.due,
      place: draft.place,
    );
  }

  Future<WishDraft?> _openForm({Wish? existing, String initialUrl = ''}) =>
      showWishFormSheet(
        context,
        theme: widget.theme,
        customKinds: _custom,
        plusGate: PlusService.instance.gate,
        groupId: widget.groupId,
        uid: widget.myUid,
        initialUrl: initialUrl,
        existing: existing,
        onCreateCategory: _createCategory,
        onEditCategory: _editCategory,
        onOfferPlus: _offerPlus,
      );

  /// Своя категория — за Togetherly+. Уже созданными пользуются оба, даже если
  /// Плюс кончился: список пары не должен схлопываться задним числом.
  Future<WishKind?> _createCategory() async {
    final draft = await showWishCategorySheet(context, theme: widget.theme);
    if (draft == null) return null;
    return _repo.addCategory(
      groupId: widget.groupId,
      title: draft.title,
      symbol: draft.symbol,
      note: draft.note,
    );
  }

  Future<void> _editCategory(WishKind kind) async {
    final draft = await showWishCategorySheet(
      context,
      theme: widget.theme,
      existing: kind,
    );
    if (draft == null) return;
    await _repo.editCategory(
      groupId: widget.groupId,
      kind: kind,
      title: draft.title,
      symbol: draft.symbol,
      note: draft.note,
    );
  }

  void _offerPlus() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlusScreen(scheme: ProfileTheme.themeFor(widget.theme).colorScheme),
        settings: const RouteSettings(name: '/plus'),
      ),
    );
  }

  Future<void> _openComments(Wish wish) => showWishCommentsSheet(
    context,
    theme: widget.theme,
    wish: wish,
    myUid: widget.myUid,
    comments: _repo.watchComments(widget.groupId),
    nameOf: _nameOf,
    onSend: (text) =>
        _repo.addComment(groupId: widget.groupId, wishId: wish.id, text: text),
    onDelete: (c) => _repo.removeComment(c.id),
  );

  /// Перетащили карточку в «мечтаем»: новое место пишет любой из пары.
  Future<void> _reorder(List<Wish> shown, int from, int to) async {
    final changed = wishReorder(shown, from, to);
    if (changed.isEmpty) return;
    setState(() => _posOverride.addAll(changed));
    final byId = {for (final w in shown) w.id: w};
    for (final e in changed.entries) {
      final w = byId[e.key];
      if (w == null) continue;
      await _repo.setPos(groupId: widget.groupId, wish: w, pos: e.value);
    }
  }

  /// «Я тоже хочу» на желании партнёра.
  Future<void> _toggleAlso(Wish wish) =>
      _repo.toggleAlso(groupId: widget.groupId, wish: wish);

  Future<void> _toggle(Wish wish) async {
    if (wish.done) {
      await _repo.undone(groupId: widget.groupId, wish: wish);
      return;
    }
    final marked = await _repo.markDone(groupId: widget.groupId, wish: wish);
    if (marked == null || !mounted) return;
    _showDoneSnack(marked);
  }

  void _showDoneSnack(Wish wish) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _cs.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 5),
        content: Text(
          '${_tr('Сбылось', 'Came true')} · ${wish.title}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFonts.onest(size: 14, color: _cs.onInverseSurface),
        ),
        action: SnackBarAction(
          label: _tr('ОТМЕНИТЬ', 'UNDO'),
          textColor: _cs.inversePrimary,
          onPressed: () => _repo.undone(groupId: widget.groupId, wish: wish),
        ),
      ),
    );
  }

  /// Дата исполнения: тап по ней в архиве.
  ///
  /// «В списке желаний отмечается дата нажатия галочки, но галочку не всегда
  /// ставят сразу. Было бы круто иметь возможность отредактировать дату»
  /// (просьба от 01.09.2026). Раньше сегодняшнего дня не ставим — сбывшееся
  /// будущим числом читалось бы ошибкой.
  Future<void> _editDoneDate(Wish wish) async {
    final now = DateTime.now();
    final base = wish.doneAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isAfter(now) ? now : base,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: _tr('Когда сбылось', 'When it happened'),
      builder: (ctx, child) =>
          Theme(data: ProfileTheme.data(_cs), child: child!),
    );
    if (picked == null) return;
    // Час оставляем прежний: человек правит день, а не минуту, а порядок в
    // архиве считается по всей отметке времени.
    await _repo.setDoneAt(
      groupId: widget.groupId,
      wish: wish,
      at: DateTime(
        picked.year,
        picked.month,
        picked.day,
        base.hour,
        base.minute,
        base.second,
      ),
    );
  }

  /// Заметка «как прошло» у сбывшегося: тап по карточке в архиве. В снекбаре
  /// второй кнопке места нет — Material оставляет действию одну.
  Future<void> _editDoneNote(Wish wish) async {
    final text = await AppDialog.prompt(
      context,
      title: _tr('Как прошло', 'How it went'),
      hint: _tr('Пара слов на память', 'A few words to remember'),
      initial: wish.doneNote,
      maxLength: 200,
      maxLines: 3,
    );
    if (text == null) return;
    await _repo.setDoneNote(groupId: widget.groupId, wish: wish, note: text);
  }

  Future<void> _remove(Wish wish) async {
    final ok = await AppDialog.confirm(
      context,
      message: LocaleService.instance.language == AppLanguage.zh
          ? '要删除“${wish.title}”吗？你们两边都会看不到它。'
          : _tr(
              'Удалить «${wish.title}»? Желание пропадёт у обоих.',
              'Delete "${wish.title}"? It will disappear for both of you.',
            ),
      confirmLabel: _tr('Удалить', 'Delete'),
      destructive: true,
    );
    if (!ok) return;
    await _repo.remove(wish.id);
  }

  // ── Экран ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _cs.surface,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _cs.surface,
        foregroundColor: _cs.onSurface,
        title: Text(
          _tr('Хочу с тобой', 'Want with you'),
          style: AppFonts.unbounded(
            size: 17,
            weight: 600,
            color: _cs.onSurface,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('wish-reminders'),
            tooltip: _tr('Напоминания', 'Reminders'),
            onPressed: _openReminderSettings,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: StableStreamBuilder<List<Wish>>(
        create: () => _repo.watch(widget.groupId),
        keys: [widget.groupId],
        builder: (context, snapshot) {
          final raw = snapshot.data ?? const <Wish>[];
          // Вернувшаяся из кэша запись с тем же местом снимает подмену.
          for (final w in raw) {
            if (_posOverride[w.id] == w.pos) _posOverride.remove(w.id);
          }
          final all = [
            for (final w in raw)
              _posOverride.containsKey(w.id)
                  ? w.copyWith(pos: _posOverride[w.id])
                  : w,
          ];
          if (snapshot.hasData) _maybeReschedule(raw);
          final dreaming = Wish.dreaming(all);
          final fulfilled = Wish.fulfilled(all);
          final shown = _fulfilledTab ? fulfilled : dreaming;

          return SafeArea(
            child: Column(
              children: [
                if (all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: _Tabs(
                      scheme: _cs,
                      dreaming:
                          '${_tr('Мечтаем', 'Dreaming')} · ${dreaming.length}',
                      fulfilled:
                          '${_tr('Сбылось', 'Came true')} · ${fulfilled.length}',
                      fulfilledSelected: _fulfilledTab,
                      onChanged: (v) => setState(() => _fulfilledTab = v),
                    ),
                  ),
                Expanded(
                  child: all.isEmpty
                      ? _empty()
                      : shown.isEmpty
                      ? _emptyTab()
                      : _fulfilledTab
                      ? ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          itemCount: shown.length + 1,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          // Сверху — вход на стену «Сбылось».
                          itemBuilder: (_, i) => i == 0
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.tonalIcon(
                                    key: const Key('wish-wall'),
                                    onPressed: () => _openWall(shown),
                                    icon: const Icon(Icons.grid_view_rounded),
                                    label: Text(
                                      wishWallButtonLabel(shown.length),
                                    ),
                                  ),
                                )
                              : _tile(shown[i - 1]),
                        )
                      // Мечты двигают долгим нажатием; порядок общий
                      // для пары (docs/WISHLIST.md).
                      : ReorderableListView.builder(
                          key: const Key('wishes-reorder'),
                          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                          buildDefaultDragHandles: false,
                          header: _weeklyCard(dreaming),
                          itemCount: shown.length,
                          onReorderItem: (from, to) =>
                              _reorder(shown, from, to),
                          itemBuilder: (_, i) =>
                              ReorderableDelayedDragStartListener(
                                key: ValueKey(shown[i].id),
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _tile(shown[i], draggable: true),
                                ),
                              ),
                        ),
                ),
                _addButton(),
              ],
            ),
          );
        },
      ),
    );
  }

  /// «Желание недели» над мечтами: одно на пару, одинаковое у обоих.
  Widget? _weeklyCard(List<Wish> dreaming) {
    if (dreaming.length < 2) return null;
    final w = weeklyWish(dreaming, widget.groupId, isoWeekKey(DateTime.now()));
    if (w == null) return null;
    return Padding(
      key: const Key('wish-weekly'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _cs.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Желание недели', 'Wish of the week'),
                      style: AppFonts.onest(
                        size: 12,
                        weight: 700,
                        color: _cs.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.unbounded(
                        size: 15,
                        weight: 600,
                        color: _cs.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('wish-weekly-another'),
                onPressed: () => _anotherWeekly(w),
                style: TextButton.styleFrom(
                  foregroundColor: _cs.onTertiaryContainer,
                ),
                child: Text(_tr('Другое', 'Another')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Карточка списка. [draggable] — в «мечтаем»: долгое нажатие там тянет
  /// карточку, а удаление остаётся в меню.
  Widget _tile(Wish wish, {bool draggable = false}) {
    final mine = wish.authorUid == widget.myUid;
    return _WishTile(
      wish: wish,
      scheme: _cs,
      ru: _ru,
      authorName: _nameOf(wish.authorUid),
      authorAvatarUrl: _avatarOf(wish.authorUid),
      onToggle: () => _toggle(wish),
      // Чужое не правим, но читать его надо целиком: в списке описание в
      // одну строку.
      onTap: wish.done
          ? () => _editDoneNote(wish)
          : mine
          ? () => _edit(wish)
          : () => showWishDetailsSheet(
              context,
              theme: widget.theme,
              wish: wish,
              authorName: _nameOf(wish.authorUid),
              alsoMine: wish.also.contains(widget.myUid),
              onAlso: () => _toggleAlso(wish),
            ),
      onLongPress: mine && !draggable ? () => _remove(wish) : null,
      // fork (D11): то же удаление — видимой кнопкой.
      onDelete: mine ? () => _remove(wish) : null,
      onEditDate: wish.done ? () => _editDoneDate(wish) : null,
      onReserve: mine ? null : () => _toggleReserve(wish),
      reserved: _reserved.contains(wish.id),
      reserveOverdue: _reservations[wish.id]?.overdue(DateTime.now()) ?? false,
      onAlso: mine || wish.done ? null : () => _toggleAlso(wish),
      alsoMine: wish.also.contains(widget.myUid),
      comments: _commentCounts[wish.id] ?? 0,
      onComments: () => _openComments(wish),
      onLinkMemory: wish.done ? () => _linkMemory(wish) : null,
      onOpenMemory:
          wish.memoryId.isNotEmpty &&
              widget.onOpenMemory != null &&
              _memories.containsKey(wish.memoryId)
          ? () => widget.onOpenMemory!(wish.memoryId)
          : null,
      onUnlinkMemory: wish.memoryId.isEmpty
          ? null
          : () => _repo.linkMemory(
              groupId: widget.groupId,
              wish: wish,
              memoryId: '',
            ),
      onShowPlace: wish.place == null
          ? null
          : () => WishPlacePicker.show(
              context,
              theme: widget.theme,
              place: wish.place!,
            ),
    );
  }

  /// Кнопка во всю ширину вместо расширенного FAB: действие тут одно, и оно
  /// главное — прятать его в угол незачем.
  Widget _addButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(_tr('Добавить', 'Add')),
          style: FilledButton.styleFrom(
            backgroundColor: _cs.primaryContainer,
            foregroundColor: _cs.onPrimaryContainer,
            shape: const StadiumBorder(),
            textStyle: AppFonts.onest(size: 16, weight: 700),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cs.primaryContainer,
              ),
              alignment: Alignment.center,
              child: SymbolIcon(
                'auto_awesome',
                size: 40,
                color: _cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _tr('Пока пусто', 'Nothing yet'),
              style: AppFonts.unbounded(
                size: 20,
                weight: 700,
                color: _cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _tr(
                'Добавьте первое желание: фильм, который ждёте, место, куда '
                    'хотите, или что-то своё. Второй половине оно появится сразу.',
                'Add your first wish: a film you are waiting for, a place you '
                    'want to go, or anything of your own. Your partner will see '
                    'it right away.',
              ),
              textAlign: TextAlign.center,
              style: AppFonts.onest(
                size: 14,
                height: 1.5,
                color: _cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          _fulfilledTab
              ? _tr(
                  'Сбывшегося пока нет. Отметьте желание галочкой, когда оно '
                      'случится.',
                  'Nothing has come true yet. Tick a wish off when '
                      'it happens.',
                )
              : _tr(
                  'Все желания сбылись. Самое время придумать новое.',
                  'Every wish came true. Time to think of a new one.',
                ),
          textAlign: TextAlign.center,
          style: AppFonts.onest(
            size: 14,
            height: 1.5,
            color: _cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Переключатель списков — связанная пара кнопок M3.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.scheme,
    required this.dreaming,
    required this.fulfilled,
    required this.fulfilledSelected,
    required this.onChanged,
  });

  final ColorScheme scheme;
  final String dreaming;
  final String fulfilled;
  final bool fulfilledSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // ClipRRect снаружи, а не clipBehavior у Container: заливка выбранной
    // половины рисуется дочерним Material и вылезала за скруглённые углы —
    // угол выглядел откушенным.
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        color: scheme.surfaceContainerHigh,
        child: Row(
          children: [
            _half(dreaming, !fulfilledSelected, () => onChanged(false)),
            _half(fulfilled, fulfilledSelected, () => onChanged(true)),
          ],
        ),
      ),
    );
  }

  Widget _half(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.onest(
                size: 13.5,
                weight: 600,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карточка желания: чекбокс, значок категории, название и подпись автора.
class _WishTile extends StatelessWidget {
  const _WishTile({
    required this.wish,
    required this.scheme,
    required this.ru,
    required this.authorName,
    required this.onToggle,
    this.authorAvatarUrl,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.onEditDate,
    this.onReserve,
    this.reserved = false,
    this.reserveOverdue = false,
    this.onAlso,
    this.alsoMine = false,
    this.comments = 0,
    this.onComments,
    this.onShowPlace,
    this.onLinkMemory,
    this.onOpenMemory,
    this.onUnlinkMemory,
  });

  final Wish wish;
  final ColorScheme scheme;
  final bool ru;
  final String authorName;
  final String? authorAvatarUrl;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// fork (D11): удалить своё желание без долгого нажатия.
  final VoidCallback? onDelete;

  /// Поправить дату исполнения: галочку ставят не в тот день, когда всё
  /// случилось, и «неправильная дата смысла не имеет».
  final VoidCallback? onEditDate;

  /// Взять вещь на себя. Null у автора желания — ему этой кнопки не видно.
  final VoidCallback? onReserve;

  /// Уже взял. Знают об этом только даритель и сервер.
  final bool reserved;

  /// Срок «Дарю» прошёл — значок подарка красным.
  final bool reserveOverdue;

  /// «Я тоже хочу» — на чужом несбывшемся желании.
  final VoidCallback? onAlso;

  /// Я уже отметил «я тоже хочу».
  final bool alsoMine;

  /// Сколько комментариев и как их открыть.
  final int comments;
  final VoidCallback? onComments;

  /// Показать точку «Места» на карте.
  final VoidCallback? onShowPlace;

  /// Сбывшееся и воспоминание: привязать, открыть, отвязать.
  final VoidCallback? onLinkMemory;
  final VoidCallback? onOpenMemory;
  final VoidCallback? onUnlinkMemory;

  @override
  Widget build(BuildContext context) {
    final done = wish.done;

    // Сбывшееся садится на контейнер ниже — тем же приёмом гаснут выполненные
    // шаги онбординга.
    final background = done
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerHigh;
    final leadBackground = done
        ? scheme.surfaceContainerHighest
        : scheme.primaryContainer;
    final leadColor = done
        ? scheme.onSurfaceVariant
        : scheme.onPrimaryContainer;

    final subtitle = <String>[
      if (authorName.isNotEmpty) authorName,
      if (wish.note.isNotEmpty) wish.note,
    ].join(' · ');

    // Хотят оба — карточка заметнее: обводка цветом темы (docs/WISHLIST.md).
    final both = wish.wantedByBoth && !done;
    final due = done ? '' : wishDueLabel(wish.due);
    final duePast = wish.due.isPast(DateTime.now());

    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: both ? Border.all(color: scheme.primary, width: 1.6) : null,
      ),
      child: _card(
        context,
        background,
        leadBackground,
        leadColor,
        subtitle,
        both,
        due,
        duePast,
      ),
    );
  }

  Widget _card(
    BuildContext context,
    Color background,
    Color leadBackground,
    Color leadColor,
    String subtitle,
    bool both,
    String due,
    bool duePast,
  ) {
    final done = wish.done;
    final s = LocaleService.current;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('wish-tile-${wish.id}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Check(checked: done, scheme: scheme, onTap: onToggle),
              const SizedBox(width: 12),
              // У вещи вместо значка категории — её фотография: список
              // желаний-товаров читается картинками, а не одинаковыми
              // кружками. Картинки нет — возвращаемся к значку.
              wish.isItem && wish.image.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      // StorageImage, а не Image.network: своё фото уходит в
                      // хранилище и приходит ссылкой `pb://`, которую обычная
                      // картинка не понимает — на её месте был бы значок.
                      child: StorageImage(
                        imageUrl: wish.image,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Container(
                          width: 56,
                          height: 56,
                          color: leadBackground,
                          alignment: Alignment.center,
                          child: SymbolIcon(
                            wish.iconName,
                            size: 24,
                            color: leadColor,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: leadBackground,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: SymbolIcon(
                        wish.iconName,
                        size: 24,
                        color: leadColor,
                      ),
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wish.title,
                      style: AppFonts.unbounded(
                        size: 17,
                        weight: done ? 500 : 600,
                        color: done
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    if (due.isNotEmpty ||
                        both ||
                        comments > 0 ||
                        wish.place != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (due.isNotEmpty)
                              _Meta(
                                icon: Icons.event_rounded,
                                label: due,
                                color: duePast
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            if (wish.place != null)
                              _Meta(
                                icon: Icons.place_rounded,
                                label: wish.place!.name.isNotEmpty
                                    ? wish.place!.name
                                    : (ru ? 'На карте' : 'On the map'),
                                color: scheme.onSurfaceVariant,
                              ),
                            if (comments > 0)
                              _Meta(
                                icon: Icons.chat_bubble_outline_rounded,
                                label: '$comments',
                                color: scheme.onSurfaceVariant,
                              ),
                            if (both)
                              _Meta(
                                icon: Icons.favorite_rounded,
                                label: ru ? 'Хотим оба' : 'We both want it',
                                color: scheme.primary,
                              ),
                          ],
                        ),
                      ),
                    if (wish.hasPrice || wish.shop.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            if (wish.hasPrice)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: done
                                      ? scheme.surfaceContainerHighest
                                      : scheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  wish.priceLabel,
                                  style: AppFonts.onest(
                                    size: 12.5,
                                    weight: 700,
                                    color: done
                                        ? scheme.onSurfaceVariant
                                        : scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            if (wish.shop.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  wish.shop,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFonts.onest(
                                    size: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (done) ...[
                      if (wish.doneAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: InkWell(
                            onTap: onEditDate,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.dayLogDate(wish.doneAt!),
                                    style: AppFonts.onest(
                                      size: 12.5,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (onEditDate != null) ...[
                                    const SizedBox(width: 5),
                                    Icon(
                                      Icons.edit_calendar_rounded,
                                      size: 14,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (wish.doneNote.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            wish.doneNote,
                            style: AppFonts.onest(
                              size: 12.5,
                              height: 1.45,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      // Воспоминание: привязать (не обязательно) или открыть.
                      if (wish.memoryId.isEmpty && onLinkMemory != null)
                        TextButton.icon(
                          key: Key('wish-link-memory-${wish.id}'),
                          onPressed: onLinkMemory,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 16,
                          ),
                          label: Text(
                            ru ? 'Привязать воспоминание' : 'Link a memory',
                            style: AppFonts.onest(size: 12.5, weight: 600),
                          ),
                        )
                      else if (wish.memoryId.isNotEmpty)
                        TextButton.icon(
                          onPressed: onOpenMemory,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            foregroundColor: scheme.primary,
                          ),
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                          ),
                          label: Text(
                            ru ? 'Воспоминание' : 'Memory',
                            style: AppFonts.onest(size: 12.5, weight: 600),
                          ),
                        ),
                    ] else if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            if (authorName.isNotEmpty) ...[
                              // AvatarWidget сам разбирается с форматом ссылки
                              // и кэшем; свой NetworkImage на аватарах из
                              // группы показывал пустой круг.
                              AvatarWidget(
                                uid: wish.authorUid,
                                liveUrl: authorAvatarUrl,
                                name: authorName,
                                size: 18,
                                primary: scheme.primary,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.onest(
                                  size: 12.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (onAlso != null)
                IconButton(
                  key: Key('wish-also-${wish.id}'),
                  tooltip: alsoMine
                      ? (ru ? 'Вы тоже хотите' : 'You want it too')
                      : (ru ? 'Я тоже хочу' : 'I want it too'),
                  onPressed: onAlso,
                  icon: Icon(
                    alsoMine
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 20,
                    color: alsoMine ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              // «Дарю» — только на чужой вещи и только пока она не сбылась.
              // Кнопки нет у автора вовсе: он и записи такой не получает,
              // а пустая кнопка выдала бы, что подарок кто-то готовит.
              if (onReserve != null && wish.isItem && !done)
                IconButton(
                  tooltip: reserved
                      ? (ru ? 'Я дарю' : "I'm gifting")
                      : (ru ? 'Дарю' : 'Gift it'),
                  onPressed: onReserve,
                  icon: Icon(
                    reserved
                        ? Icons.card_giftcard_rounded
                        : Icons.redeem_outlined,
                    size: 20,
                    color: reserveOverdue
                        ? scheme.error
                        : reserved
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              if (wish.url.isNotEmpty || onDelete != null || onComments != null)
                PopupMenuButton<String>(
                  key: Key('wish-menu-${wish.id}'),
                  tooltip: ru ? 'Действия с желанием' : 'Wish actions',
                  onSelected: (action) async {
                    if (action == 'delete') {
                      onDelete?.call();
                      return;
                    }
                    if (action == 'comments') {
                      onComments?.call();
                      return;
                    }
                    if (action == 'map') {
                      onShowPlace?.call();
                      return;
                    }
                    if (action == 'link') {
                      onLinkMemory?.call();
                      return;
                    }
                    if (action == 'unlink') {
                      onUnlinkMemory?.call();
                      return;
                    }
                    final uri = Uri.tryParse(wish.url);
                    if (uri != null)
                      await safeLaunchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                  },
                  itemBuilder: (_) => [
                    if (onLinkMemory != null)
                      PopupMenuItem(
                        value: 'link',
                        child: Text(
                          wish.memoryId.isEmpty
                              ? (ru
                                    ? 'Привязать воспоминание'
                                    : 'Link a memory')
                              : (ru ? 'Другое воспоминание' : 'Another memory'),
                        ),
                      ),
                    if (onUnlinkMemory != null)
                      PopupMenuItem(
                        value: 'unlink',
                        child: Text(
                          ru ? 'Отвязать воспоминание' : 'Unlink the memory',
                        ),
                      ),
                    if (onShowPlace != null)
                      PopupMenuItem(
                        value: 'map',
                        child: Text(
                          ru ? 'Показать на карте' : 'Show on the map',
                        ),
                      ),
                    if (onComments != null)
                      PopupMenuItem(
                        value: 'comments',
                        child: Text(
                          ru
                              ? (comments > 0
                                    ? 'Комментарии · $comments'
                                    : 'Комментировать')
                              : (comments > 0
                                    ? 'Comments · $comments'
                                    : 'Comment'),
                        ),
                      ),
                    if (wish.url.isNotEmpty)
                      PopupMenuItem(
                        value: 'open',
                        child: Text(ru ? 'Открыть ссылку' : 'Open link'),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(ru ? 'Удалить' : 'Delete'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка-примета под названием: срок, «хотим оба».
class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppFonts.onest(size: 12.5, weight: 600, color: color),
        ),
      ],
    );
  }
}

/// Чекбокс M3 со своей зоной нажатия: он и есть отметка «сбылось», поэтому
/// живёт отдельно от тапа по карточке.
class _Check extends StatelessWidget {
  const _Check({
    required this.checked,
    required this.scheme,
    required this.onTap,
  });

  final bool checked;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Padding(
          // Палец получает 48 точек, сам квадрат остаётся 20 — как в макете.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(.2, 0, 0, 1),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: checked ? scheme.primary : Colors.transparent,
              border: Border.all(
                color: checked ? scheme.primary : scheme.outline,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: checked
                ? Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)
                : null,
          ),
        ),
      ),
    );
  }
}
