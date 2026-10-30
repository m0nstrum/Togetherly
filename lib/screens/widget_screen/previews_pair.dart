import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../models/together_milestones.dart';
import '../../widgets/miss_widget_card.dart';
import '../../widgets/together_track_card.dart';
import '../../services/widget_theme_sync.dart';
import '../../utils/couple_days.dart';
import '../../widgets/avatar_widget.dart';
import '../../models/pair_data.dart';
import '../../models/timer_item.dart';
import '../../models/user_data.dart';
import '../../models/mood_entry.dart';
import '../../services/locale_service.dart';
import '../../services/mood_service.dart';
import '../../services/timer_service.dart';
import '../../services/widget_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/petal_timer_dial.dart';
import '../../widgets/mood_hearts_preview.dart';
import 'preview_parts.dart';
import 'preview_style.dart';

// Превью парных виджетов: настроение, «Вместе», «Скучаю», статистика и
// лепестковый таймер. Данные экрана приходят параметрами.

/// Превью «Настроение» 2×2: отметки обоих и три кнопки выбора.
class MoodTiles2x2Preview extends StatelessWidget {
  const MoodTiles2x2Preview({
    super.key,
    required this.ps,
    required this.moodService,
    required this.pair,
    required this.partnerGender,
  });

  final PreviewStyle ps;
  final MoodService moodService;
  final PairData pair;
  final String partnerGender;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final partnerUid = pair.partnerUid;
    final myEntry = moodService.myEntriesForDay(today).firstOrNull;
    final partnerEntry = partnerUid.isEmpty
        ? null
        : moodService.partnerEntriesForDay(partnerUid, today).firstOrNull;
    final partnerName = pair.partnerDisplayName.trim();

    Widget line(String text, Color dot, bool filled) => Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: filled ? dot : ps.wr('outline'),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ps.wr('onSurface'),
              ),
            ),
          ),
        ],
      ),
    );

    Widget pick(IconData icon, bool active) => Expanded(
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: active ? ps.wr('primaryContainer') : ps.wr('surfaceContainer'),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          size: 17,
          color: active
              ? ps.wr('onPrimaryContainer')
              : ps.wr('onSurfaceVariant'),
        ),
      ),
    );

    final myId = myEntry?.moodId ?? '';
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: ps.wr('surface'),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleService.current.tgMoodToday,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: ps.wr('onSurfaceVariant'),
              ),
            ),
            const SizedBox(height: 4),
            line(
              myEntry == null
                  ? '${LocaleService.current.tgMoodMe} · ${LocaleService.current.tgMoodNotSet}'
                  : '${LocaleService.current.tgMoodMe} · ${myEntry.labelFor(MoodGenders.mine)}',
              ps.wr('primary'),
              myEntry != null,
            ),
            line(
              partnerEntry == null
                  ? '${partnerName.isEmpty ? LocaleService.current.tgMoodPartner : partnerName} · ${LocaleService.current.tgMoodNotSet}'
                  : '${partnerName.isEmpty ? LocaleService.current.tgMoodPartner : partnerName} · ${partnerEntry.labelFor(partnerGender)}',
              ps.wr('tertiary'),
              partnerEntry != null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                pick(Icons.sentiment_very_satisfied_rounded, myId == 'happy'),
                const SizedBox(width: 6),
                pick(Icons.sentiment_neutral_rounded, myId == 'no_emotion'),
                const SizedBox(width: 6),
                pick(Icons.sentiment_dissatisfied_rounded, myId == 'sad'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Превью «Настроение» 4×2: неделя двумя рядами столбиков.
class MoodTiles4x2Preview extends StatelessWidget {
  const MoodTiles4x2Preview({
    super.key,
    required this.ps,
    required this.moodService,
    required this.pair,
  });

  final PreviewStyle ps;
  final MoodService moodService;
  final PairData pair;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final partnerUid = pair.partnerUid;
    final monday = today.subtract(Duration(days: today.weekday - 1));

    double heightOf(MoodEntry? e) =>
        e == null ? -1 : ((e.score - 1) / 4) * 0.8 + 0.2;

    final bars = <List<double>>[];
    var matched = 0;
    for (var i = 0; i < 7; i++) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final mine = moodService.myEntriesForDay(day).firstOrNull;
      final theirs = partnerUid.isEmpty
          ? null
          : moodService.partnerEntriesForDay(partnerUid, day).firstOrNull;
      bars.add([heightOf(mine), heightOf(theirs)]);
      if (mine != null && theirs != null && mine.score == theirs.score)
        matched++;
    }

    final labels = LocaleService.current.shortWeekdays
        .map((d) => d.toLowerCase())
        .toList();

    Widget bar(double value, Color color) => Expanded(
      child: FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        // Отрицательное значение — день без отметки: рисуем подложку.
        heightFactor: value < 0 ? 0.12 : value,
        child: Container(
          decoration: BoxDecoration(
            color: value < 0 ? ps.wr('surfaceContainer') : color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );

    return AspectRatio(
      aspectRatio: 424 / 200,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        decoration: BoxDecoration(
          color: ps.wr('surface'),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleService.current.tgMoodWeekTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: ps.wr('onSurfaceVariant'),
                    ),
                  ),
                ),
                if (matched > 0)
                  Text(
                    LocaleService.current.tgMoodMatched(matched),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ps.wr('outline'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 9),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(bars[i].first, ps.wr('primary')),
                          const SizedBox(width: 3),
                          bar(bars[i].last, ps.wr('tertiary')),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: ps.wr('outline'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Превью «Вместе» для каталога: тот же растр и та же дорожка, что рисует
/// натив, и те же вехи — считает их общая модель, а не экран.
class TogetherPreview extends StatelessWidget {
  const TogetherPreview({
    super.key,
    required this.cs,
    required this.ps,
    required this.userData,
    required this.pair,
    required this.togetherDays,
    required this.togetherStart,
    required this.size,
  });

  final ColorScheme cs;
  final PreviewStyle ps;
  final UserData userData;
  final PairData pair;
  final int togetherDays;
  final DateTime? togetherStart;
  final TogetherCardSize size;

  @override
  Widget build(BuildContext context) {
    final togetherStart = this.togetherStart;

    final start = togetherStart;
    final days = togetherDays;
    final track = start == null
        ? null
        : milestoneTrack(
            start: start,
            today: DateTime.now(),
            anniversary: pair.anniversaryDate,
          );
    final labels = track == null
        ? null
        : trackLabels(
            track,
            LocaleService.current,
            LocaleService.current.dayLogDate,
          );

    Widget face(String uid, String url, String name, Color bg, Color fg) =>
        Container(
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: size == TogetherCardSize.large
                  ? ps.wr('surface')
                  : ps.wr('primary'),
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: url.isNotEmpty
              ? AvatarWidget(
                  uid: uid,
                  liveUrl: url,
                  name: name,
                  size: 30,
                  primary: bg,
                )
              : Text(
                  ps.initialOf(name),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
        );

    return AspectRatio(
      aspectRatio: switch (size) {
        TogetherCardSize.small => 1,
        TogetherCardSize.medium => 338 / 158,
        TogetherCardSize.large => 1,
      },
      child: TogetherTrackCard(
        size: size,
        days: days,
        daysLabel: LocaleService.current.tgDaysTogetherCaption(days),
        percent: track?.percent ?? 0,
        roles: WidgetThemeSync.rolesOf(cs),
        startDate: start == null
            ? ''
            : 'С ${LocaleService.current.dayLogDate(start)} ${start.year}',
        names: [
          userData.displayName.trim(),
          pair.partnerDisplayName.trim(),
        ].where((n) => n.isNotEmpty).join(' + '),
        previousTitle: labels?.previousTitle ?? '',
        previousSub: labels?.previousSub ?? '',
        todayTitle: labels?.todayTitle ?? '',
        todaySub: labels?.todaySub ?? '',
        nextTitle: labels?.nextTitle ?? '',
        nextSub: labels?.nextSub ?? '',
        anniversaryTitle: labels?.anniversaryTitle ?? '',
        anniversarySub: labels?.anniversarySub ?? '',
        myAvatar: face(
          userData.uid,
          userData.avatarUrl,
          userData.displayName,
          ps.wr('avatarMine'),
          ps.wr('onPrimaryContainer'),
        ),
        partnerAvatar: face(
          pair.partnerUid,
          pair.partnerAvatarUrl,
          pair.partnerDisplayName,
          ps.wr('avatarPartner'),
          ps.wr('onTertiaryContainer'),
        ),
      ),
    );
  }
}

/// Превью «Скучаю» для каталога: тот же вид, что на рабочем столе.
class MissPreview extends StatelessWidget {
  const MissPreview({
    super.key,
    required this.cs,
    required this.ps,
    required this.userData,
    required this.missCounts,
    required this.pair,
    required this.size,
  });

  final ColorScheme cs;
  final PreviewStyle ps;
  final UserData userData;
  final Map<String, int> missCounts;
  final PairData pair;
  final MissCardSize size;

  @override
  Widget build(BuildContext context) {
    final myCount = missCounts[userData.uid] ?? 0;
    final partnerCount = missCounts[pair.partnerUid] ?? 0;
    final s = LocaleService.current;

    Widget face(String uid, String url, String name, Color bg, Color fg) =>
        Container(
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: url.isNotEmpty
              ? AvatarWidget(
                  uid: uid,
                  liveUrl: url,
                  name: name,
                  size: 26,
                  primary: bg,
                )
              : Text(
                  ps.initialOf(name),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
        );

    return AspectRatio(
      aspectRatio: switch (size) {
        MissCardSize.small => 1,
        MissCardSize.medium => 338 / 158,
        MissCardSize.strip => 338 / 74,
      },
      child: MissWidgetCard(
        size: size,
        myCount: myCount,
        partnerCount: partnerCount,
        roles: WidgetThemeSync.rolesOf(cs),
        meLabel: s.tgMissMe,
        partnerName: pair.partnerDisplayName.trim(),
        sendLabel: s.tgMissTitle,
        whenLabel: s.tgMissToday,
        myFace: face(
          userData.uid,
          userData.avatarUrl,
          userData.displayName,
          ps.wr('avatarMine'),
          ps.wr('onPrimaryContainer'),
        ),
        partnerFace: face(
          pair.partnerUid,
          pair.partnerAvatarUrl,
          pair.partnerDisplayName,
          ps.wr('avatarPartner'),
          ps.wr('onTertiaryContainer'),
        ),
      ),
    );
  }
}

class RelationshipStatsPreview extends StatelessWidget {
  const RelationshipStatsPreview({
    super.key,
    required this.t,
    required this.drawingsCount,
    required this.memoriesCount,
    required this.missYouCount,
    required this.pair,
    required this.timerService,
  });

  final AppTheme t;
  final int? drawingsCount;
  final int? memoriesCount;
  final int? missYouCount;
  final PairData pair;
  final TimerService timerService;

  @override
  Widget build(BuildContext context) {
    final drawingsCount = this.drawingsCount;
    final memoriesCount = this.memoriesCount;
    final missYouCount = this.missYouCount;

    final s = LocaleService.current;
    final sysTimer = timerService.systemTimer;
    final start = sysTimer?.startDate ?? pair.startDate;
    final daysNum = start != null
        ? calendarDaysBetween(start, DateTime.now())
        : 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.cardBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SmallStatBox(
                  t: t,
                  icon: Icons.calendar_today_rounded,
                  color: t.iconCalendar,
                  value: '$daysNum',
                  label: s.daysTogetherStat,
                  bg: t.iconCalendar.withOpacity(0.08),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmallStatBox(
                  t: t,
                  icon: Icons.photo_library_rounded,
                  color: t.iconPost,
                  value: '${memoriesCount ?? 0}',
                  label: s.memoriesStat,
                  bg: t.iconPost.withOpacity(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmallStatBox(
                  t: t,
                  icon: Icons.brush_rounded,
                  color: t.iconDraw,
                  value: '${drawingsCount ?? 0}',
                  label: s.drawingsStat,
                  bg: t.iconDraw.withOpacity(0.08),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmallStatBox(
                  t: t,
                  icon: Icons.favorite_rounded,
                  color: t.primary,
                  value: '${missYouCount ?? 0}',
                  label: s.missYousStat,
                  bg: t.primary.withOpacity(0.08),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PetalTimerPreview extends StatelessWidget {
  const PetalTimerPreview({
    super.key,
    required this.t,
    required this.widgetTimer,
  });

  final AppTheme t;
  final TimerItem? widgetTimer;

  @override
  Widget build(BuildContext context) {
    final widgetTimer = this.widgetTimer;

    final timer = widgetTimer;

    if (timer == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: t.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.primary.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            Icon(Icons.timer_off_rounded, size: 36, color: t.textMuted),
            const SizedBox(height: 8),
            Text(
              LocaleService.current.noTimersWidget,
              style: AppFonts.onest(size: 13, color: t.textMuted),
            ),
          ],
        ),
      );
    }

    return Center(
      child: RepaintBoundary(
        child: SizedBox(
          width: 200,
          height: 200,
          child: PetalTimerDial(
            theme: t,
            startDate: timer.startDate,
            isCountdown: timer.isCountdown,
          ),
        ),
      ),
    );
  }
}

class MoodPreview extends StatelessWidget {
  const MoodPreview({
    super.key,
    required this.t,
    required this.moodService,
    required this.pair,
    required this.ws,
  });

  final AppTheme t;
  final MoodService moodService;
  final PairData pair;
  final WidgetService ws;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final today = DateTime.now();

    final myEntries = moodService.myEntriesForDay(today);
    final partnerUid = pair.partners.isNotEmpty ? pair.partners.first.uid : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];

    final myName = ws.myData?.displayName.isNotEmpty == true
        ? ws.myData!.displayName
        : s.me;
    final partnerName = pair.partnerName.isNotEmpty
        ? pair.partnerName
        : s.partner;

    return MoodHeartsPreview(
      myEntries: myEntries,
      partnerEntries: partnerEntries,
      myName: myName,
      partnerName: partnerName,
      primaryColor: t.primary,
    );
  }
}
