/// Страница партнёра под шапкой профиля (просьба владельца 22.10: «экран о
/// пользователе выглядит супер пусто»).
///
/// Раньше под шапкой стояли только полка подарков и столбики «скучаю» — в
/// форке подарки без денег, и оба блока обычно пустовали. Теперь здесь то,
/// что приложение и так знает о партнёре: в сети ли он и сколько у него
/// времени, быстрые действия, настроение и статус, дата рождения, пара в
/// цифрах и ссылки на общее. Пустые строки не рисуются вовсе.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/mood_entry.dart';
import '../../models/widget_data.dart';
import '../../screens/chat/chat_search_screen.dart';
import '../../screens/couple_stats_screen.dart';
import '../../screens/gifts/gift_profile_body.dart';
import '../../screens/live_map_screen.dart';
import '../../screens/together/together_launcher.dart';
import '../../screens/wishes_screen.dart';
import '../../services/couple_stats_service.dart';
import '../../services/live_location_service.dart';
import '../../services/locale_service.dart';
import '../../services/miss_you_repository.dart';
import '../../services/mood_repository.dart';
import '../../services/pb_auth_service.dart';
import '../../services/pb_data_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/presence_service.dart';
import '../../services/wish_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/pair_time.dart';
import '../../widgets/common/stable_stream_builder.dart';
import '../../widgets/mood_image.dart';
import '../watch/pair_call.dart';

/// Что известно о партнёре. Каждое поле может быть пустым — тогда его строки
/// нет на экране.
class ForkPartnerFacts {
  const ForkPartnerFacts({
    this.mood,
    this.zone,
    this.status = '',
    this.note = '',
    this.music = '',
    this.birthday,
    this.gender = '',
    this.memories = 0,
    this.messages = 0,
    this.wishes = 0,
    this.gifts = 0,
    this.missYou = 0,
    this.startDate,
    this.anniversary,
  });

  /// Настроение за сегодня.
  final MoodEntry? mood;

  /// Часовой пояс партнёра (из его последней отметки настроения).
  final Duration? zone;
  final String status;
  final String note;
  final String music;
  final DateTime? birthday;
  final String gender;
  final int memories;
  final int messages;
  final int wishes;
  final int gifts;
  final int missYou;
  final DateTime? startDate;
  final DateTime? anniversary;

  bool get hasNow => mood != null || status.isNotEmpty || note.isNotEmpty || music.isNotEmpty;

  /// «у неё», «у него» — по полу из карточки.
  String get theirs => switch (gender) {
        'female' => ruEn('у неё', 'their'),
        'male' => ruEn('у него', 'their'),
        _ => ruEn('у партнёра', 'their'),
      };

  /// Местное время партнёра, если пояс отличается от нашего; иначе null.
  DateTime? localTime(DateTime now) {
    final z = zone;
    if (z == null || z == now.timeZoneOffset) return null;
    return now.toUtc().add(z);
  }

  /// Через сколько дней ближайший день рождения (0 — сегодня).
  static int? daysToBirthday(DateTime? birth, DateTime now) {
    if (birth == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(now.year, birth.month, birth.day);
    if (next.isBefore(today)) next = DateTime(now.year + 1, birth.month, birth.day);
    return next.difference(today).inDays;
  }

  /// Собрать по сервисам; каждый источник сам по себе — упавший не мешает
  /// остальным.
  static Future<ForkPartnerFacts> load({
    required String groupId,
    required String uid,
    Map<String, dynamic>? card,
  }) async {
    Future<T?> safe<T>(Future<T?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        debugPrint('ForkPartnerFacts: $e');
        return null;
      }
    }

    final data = PbDataService();
    final moodsF = safe(() => MoodRepository().load(groupId, uid));
    final recF = safe(() => data.loadWidget(groupId, uid));
    final statsF = safe(() => CoupleStatsService.load(groupId));
    final wishesF = safe(() => WishRepository.instance.load(groupId));
    final giftsF = safe(() => data.fetchGiftsFor(groupId: groupId, uid: uid));
    final missF = safe(() => data.fetchMissYouFor(groupId: groupId, uid: uid));
    final moods = await moodsF ?? const <MoodEntry>[];
    final rec = await recF;
    final stats = await statsF;
    final wishes = await wishesF;
    final gifts = await giftsF;
    final miss = await missF;

    WidgetData? w;
    if (rec != null) w = await safe(() async => WidgetData.fromPb(rec));

    final now = DateTime.now();
    final sorted = [...moods]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    MoodEntry? today;
    for (final m in sorted) {
      final d = m.authorDate;
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        today = m;
        break;
      }
    }
    Duration? zone;
    for (final m in sorted) {
      zone = PairTime.zoneToDuration(m.zone);
      if (zone != null) break;
    }
    final music = [w?.musicTitle ?? '', w?.musicArtist ?? '']
        .where((x) => x.trim().isNotEmpty)
        .join(' — ');
    return ForkPartnerFacts(
      mood: today,
      zone: zone,
      status: (w?.status ?? '').trim(),
      note: (w?.message ?? '').trim(),
      music: music,
      birthday: DateTime.tryParse('${card?['birthDate'] ?? ''}'),
      gender: '${card?['gender'] ?? w?.gender ?? ''}',
      memories: stats?.total('memories') ?? 0,
      messages: stats?.total('messages') ?? 0,
      wishes: wishes?.where((x) => x.authorUid == uid).length ?? 0,
      gifts: gifts?.length ?? 0,
      missYou: (miss?['count'] as num?)?.toInt() ?? 0,
      startDate: stats?.startDate,
      anniversary: stats?.anniversary,
    );
  }
}

class ForkPartnerPage extends StatefulWidget {
  const ForkPartnerPage({
    super.key,
    required this.theme,
    required this.groupId,
    required this.partnerUid,
    required this.partnerName,
    this.partnerAvatarUrl,
    this.daysTogether,
    this.card,
    @visibleForTesting this.facts,
    @visibleForTesting this.live = true,
  });

  final AppTheme theme;
  final String groupId;
  final String partnerUid;
  final String partnerName;
  final String? partnerAvatarUrl;
  final int? daysTogether;

  /// Карточка партнёра (`loadPartnerCard`): дата рождения и пол.
  final Map<String, dynamic>? card;

  /// Готовые факты вместо загрузки (тесты).
  final ForkPartnerFacts? facts;

  /// false — без живых потоков присутствия и геопозиции (тесты).
  final bool live;

  @override
  State<ForkPartnerPage> createState() => ForkPartnerPageState();
}

class ForkPartnerPageState extends State<ForkPartnerPage> {
  ForkPartnerFacts? _facts;
  bool _missSent = false;

  @override
  void initState() {
    super.initState();
    _facts = widget.facts;
    if (_facts == null) unawaited(reload());
  }

  @override
  void didUpdateWidget(ForkPartnerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Карточка с датой рождения приезжает позже — перечитаем.
    if (oldWidget.card != widget.card && widget.facts == null) unawaited(reload());
  }

  Future<void> reload() async {
    final f = await ForkPartnerFacts.load(groupId: widget.groupId, uid: widget.partnerUid, card: widget.card);
    if (mounted) setState(() => _facts = f);
  }

  String get _name => widget.partnerName.trim().isEmpty ? ruEn('Партнёр', 'Partner') : widget.partnerName.trim();
  String get _myUid => PocketBaseService().userId ?? '';

  Future<void> _miss() async {
    if (_missSent) return;
    final ok = await MissYouRepository().sendMissYou(widget.groupId);
    if (!mounted) return;
    setState(() => _missSent = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(ok ? ruEn('$_name узнает, что вы скучаете', '$_name will know you miss them') : LocaleService.current.error),
    ));
  }

  void _call() {
    ForkPairCall.instance.partnerName = widget.partnerName;
    unawaited(ForkPairCall.instance.call(widget.groupId));
  }

  void _map() {
    final me = PbAuthService().currentProfile() ?? const <String, dynamic>{};
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LiveMapScreen(
        pairId: widget.groupId,
        partnerUid: widget.partnerUid,
        partnerName: widget.partnerName,
        partnerAvatarUrl: widget.partnerAvatarUrl ?? '',
        myAvatarUrl: (me['avatarUrl'] as String?) ?? '',
        theme: widget.theme,
      ),
      settings: const RouteSettings(name: '/live_map'),
    ));
  }

  void _wishes() {
    final me = PbAuthService().currentProfile() ?? const <String, dynamic>{};
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WishesScreen(
        theme: widget.theme,
        groupId: widget.groupId,
        myUid: _myUid,
        myName: PocketBaseService().userName,
        partnerUid: widget.partnerUid,
        partnerName: widget.partnerName,
        myAvatarUrl: me['avatarUrl'] as String?,
        partnerAvatarUrl: widget.partnerAvatarUrl,
      ),
      settings: const RouteSettings(name: '/wishes'),
    ));
  }

  void _chatSearch() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatSearchScreen(groupId: widget.groupId, myUid: _myUid),
      settings: const RouteSettings(name: '/chat_search'),
    ));
  }

  void _stats() {
    final f = _facts;
    unawaited(openCoupleStats(
      context,
      theme: widget.theme,
      groupId: widget.groupId,
      myUid: _myUid,
      startDate: f?.startDate,
      anniversaryDate: f?.anniversary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = _facts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.live) _presence(cs, f),
        const SizedBox(height: 16),
        _actions(cs),
        if (f == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (f.hasNow || widget.live) _now(cs, f),
          _dates(cs, f),
          _together(cs, f),
          _shared(cs, f),
          if (f.gifts > 0 || f.missYou > 0) ...[
            _Head(ruEn('Подарки и «скучаю»', 'Gifts and “miss you”')),
            GiftProfileBody(
              theme: widget.theme,
              groupId: widget.groupId,
              uid: widget.partnerUid,
              name: widget.partnerName,
              avatarUrl: widget.partnerAvatarUrl,
              daysTogether: widget.daysTogether,
              showHeader: false,
              showMissWeek: f.missYou > 0,
            ),
          ],
        ],
      ],
    );
  }

  /// «в сети» или «был(а) в 12:33»; у партнёра другой пояс — его время.
  Widget _presence(ColorScheme cs, ForkPartnerFacts? f) {
    final uid = widget.partnerUid;
    return StableStreamBuilder<bool>(
      create: () => PresenceService().watchOnline(uid),
      keys: [uid],
      builder: (context, on) => StableStreamBuilder<int?>(
        create: () => PresenceService().watchLastSeen(uid),
        keys: [uid],
        builder: (context, seen) {
          final online = on.data == true;
          final parts = <String>[
            online ? ruEn('в сети', 'online') : _seenLabel(seen.data),
          ];
          final local = f?.localTime(DateTime.now());
          if (local != null) {
            parts.add(ruEn('${f!.theirs} сейчас ${_hhmm(local)}', '${_hhmm(local)} for them'));
          }
          final text = parts.where((x) => x.isNotEmpty).join(' · ');
          if (text.isEmpty) return const SizedBox.shrink();
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online ? const Color(0xFF2E9E5B) : cs.outline,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    key: const ValueKey('fork-partner-presence'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _seenLabel(int? ms) {
    if (ms == null || ms <= 0) return '';
    final seen = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(seen.year, seen.month, seen.day);
    if (day == today) return ruEn('заходил(а) в ${_hhmm(seen)}', 'last seen at ${_hhmm(seen)}');
    if (day == today.subtract(const Duration(days: 1))) {
      return ruEn('заходил(а) вчера в ${_hhmm(seen)}', 'last seen yesterday at ${_hhmm(seen)}');
    }
    final d = '${seen.day.toString().padLeft(2, '0')}.${seen.month.toString().padLeft(2, '0')}';
    return ruEn('заходил(а) $d', 'last seen $d');
  }

  Widget _actions(ColorScheme cs) {
    final items = <(IconData, String, VoidCallback, Key)>[
      (Icons.call_rounded, ruEn('Позвонить', 'Call'), _call, const ValueKey('fork-partner-call')),
      (
        _missSent ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ruEn('Скучаю', 'Miss you'),
        () => unawaited(_miss()),
        const ValueKey('fork-partner-miss'),
      ),
      (
        Icons.smart_display_rounded,
        ruEn('Смотреть', 'Watch'),
        () => unawaited(TogetherLauncher.open(context, pairId: widget.groupId)),
        const ValueKey('fork-partner-watch'),
      ),
      (Icons.place_rounded, ruEn('Где ты', 'Where'), _map, const ValueKey('fork-partner-map')),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, label, onTap, key) in items)
          Expanded(
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                      child: Icon(icon, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurface)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _now(ColorScheme cs, ForkPartnerFacts f) {
    final rows = <Widget>[
      if (f.mood != null)
        _Row(
          lead: SizedBox(width: 28, height: 28, child: MoodImage(f.mood!.imagePath, quietError: true)),
          title: f.mood!.labelFor(f.gender),
          sub: ruEn('настроение сегодня', 'mood today'),
        ),
      if (f.status.isNotEmpty) _Row(icon: Icons.chat_bubble_outline_rounded, title: f.status, sub: ruEn('статус', 'status')),
      if (f.note.isNotEmpty) _Row(icon: Icons.sticky_note_2_outlined, title: f.note, sub: ruEn('записка на виджете', 'widget note')),
      if (f.music.isNotEmpty) _Row(icon: Icons.music_note_rounded, title: f.music, sub: ruEn('слушает', 'listening to')),
      if (widget.live) _distance(cs),
    ];
    return _Section(title: ruEn('Сейчас', 'Now'), children: rows);
  }

  /// Расстояние — только если обе точки известны.
  Widget _distance(ColorScheme cs) {
    final svc = LiveLocationService.instance;
    return StableStreamBuilder<LivePoint?>(
      create: () => svc.watchPartner(widget.groupId, widget.partnerUid),
      keys: [widget.groupId, widget.partnerUid],
      builder: (context, them) => StableStreamBuilder<LivePoint?>(
        create: () => svc.watchSelf(widget.groupId, widget.partnerUid),
        keys: [widget.groupId, widget.partnerUid],
        builder: (context, me) {
          final a = them.data, b = me.data;
          if (a == null || b == null) return const SizedBox.shrink();
          final m = LiveLocationService.distanceMeters(LatLng(a.lat, a.lng), LatLng(b.lat, b.lng));
          return _Row(
            icon: Icons.near_me_rounded,
            title: LocaleService.current.distanceLabel(m),
            sub: ruEn('между вами', 'between you'),
            onTap: _map,
          );
        },
      ),
    );
  }

  Widget _dates(ColorScheme cs, ForkPartnerFacts f) {
    final now = DateTime.now();
    final left = ForkPartnerFacts.daysToBirthday(f.birthday, now);
    final b = f.birthday;
    final rows = <Widget>[
      if (b != null && left != null)
        _Row(
          icon: Icons.cake_outlined,
          title: '${b.day.toString().padLeft(2, '0')}.${b.month.toString().padLeft(2, '0')}',
          sub: left == 0
              ? ruEn('день рождения сегодня!', 'birthday today!')
              : ruEn('день рождения через $left ${_days(left)}', 'birthday in $left days'),
        ),
      if (f.anniversary != null)
        _Row(
          icon: Icons.favorite_outline_rounded,
          title: '${f.anniversary!.day.toString().padLeft(2, '0')}.${f.anniversary!.month.toString().padLeft(2, '0')}.${f.anniversary!.year}',
          sub: ruEn('годовщина', 'anniversary'),
        ),
    ];
    return _Section(title: ruEn('Даты', 'Dates'), children: rows);
  }

  static String _days(int n) {
    final a = n % 10, b = n % 100;
    if (a == 1 && b != 11) return 'день';
    if (a >= 2 && a <= 4 && (b < 12 || b > 14)) return 'дня';
    return 'дней';
  }

  /// Пара в цифрах — плитками; касание ведёт в статистику.
  Widget _together(ColorScheme cs, ForkPartnerFacts f) {
    final tiles = <(String, String)>[
      if ((widget.daysTogether ?? 0) > 0) ('${widget.daysTogether}', ruEn('дней вместе', 'days together')),
      if (f.memories > 0) ('${f.memories}', ruEn('воспоминаний', 'memories')),
      if (f.messages > 0) ('${f.messages}', ruEn('сообщений', 'messages')),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const ValueKey('fork-partner-stats'),
          borderRadius: BorderRadius.circular(20),
          onTap: _stats,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: [
                for (final (n, label) in tiles)
                  Expanded(
                    child: Column(
                      children: [
                        Text(n, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shared(ColorScheme cs, ForkPartnerFacts f) => _Section(
        title: ruEn('Общее', 'Shared'),
        children: [
          _Row(
            icon: Icons.card_giftcard_rounded,
            title: ruEn('Желания $_name', '$_name’s wishes'),
            trailing: f.wishes > 0 ? '${f.wishes}' : null,
            onTap: _wishes,
          ),
          _Row(
            icon: Icons.manage_search_rounded,
            title: ruEn('Голосовые, кружочки и ссылки', 'Voice, video notes and links'),
            sub: ruEn('поиск по переписке', 'search the chat'),
            onTap: _chatSearch,
          ),
          _Row(
            icon: Icons.insights_rounded,
            title: ruEn('Статистика пары', 'Couple stats'),
            onTap: _stats,
          ),
        ],
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

/// Блок со строками; без строк — не рисуется.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(title),
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.icon, this.lead, this.sub, this.trailing, this.onTap});

  final IconData? icon;
  final Widget? lead;
  final String title;
  final String? sub;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: lead ?? (icon == null ? null : Icon(icon, color: cs.primary)),
      title: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: sub == null ? null : Text(sub!),
      trailing: trailing != null
          ? Text(trailing!, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))
          : onTap != null
              ? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant)
              : null,
    );
  }
}
