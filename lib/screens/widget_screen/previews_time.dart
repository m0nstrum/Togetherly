import 'package:flutter/material.dart';
import '../../models/year_ring_spec.dart';
import '../../widgets/year_ring_card.dart';
import '../../models/timer_item.dart';
import '../../models/year_progress.dart';
import '../../services/locale_service.dart';
import 'preview_style.dart';

// Превью виджетов «До встречи», «Кольцо года», «Календарь лет» и плитка
// маскота: данные экрана приходят параметрами.

/// Превью «До встречи» 2×2.
class Countdown2x2Preview extends StatelessWidget {
  const Countdown2x2Preview({
    super.key,
    required this.ps,
    required this.nextEvent,
  });

  final PreviewStyle ps;
  final TimerItem? nextEvent;

  @override
  Widget build(BuildContext context) {
    final nextEvent = this.nextEvent;

    final event = nextEvent;
    final left = event == null
        ? Duration.zero
        : event.startDate.difference(DateTime.now());

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: ps.wr('tertiaryContainer'),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event == null
                  ? LocaleService.current.tgCountdownEmpty
                  : '${event.title} · ${ps.formatDayMonth(event.startDate)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ps.wr('tertiary'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              event == null ? '—' : '${left.inDays}',
              style: TextStyle(
                fontSize: 40,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
                color: ps.wr('onTertiaryContainer'),
              ),
            ),
            Text(
              LocaleService.current.tgCountdownDaysLeft(left.inDays),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ps.wr('onTertiaryContainer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Превью «До встречи» 4×2: дни, часы, минуты и прогресс.
class Countdown4x2Preview extends StatelessWidget {
  const Countdown4x2Preview({
    super.key,
    required this.ps,
    required this.nextEvent,
    required this.togetherStart,
  });

  final PreviewStyle ps;
  final TimerItem? nextEvent;
  final DateTime? togetherStart;

  @override
  Widget build(BuildContext context) {
    final nextEvent = this.nextEvent;
    final togetherStart = this.togetherStart;

    final event = nextEvent;
    final now = DateTime.now();
    final left = event == null
        ? Duration.zero
        : event.startDate.difference(now);

    final from = togetherStart ?? now.subtract(const Duration(days: 30));
    final total = event == null
        ? 0
        : event.startDate.difference(from).inMinutes;
    final passed = now.difference(from).inMinutes;
    final percent = (event == null || total <= 0)
        ? 0.0
        : (passed / total).clamp(0.0, 1.0);

    Widget tile(String value, String label, Color bg, Color fg, Color sub) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: sub,
                  ),
                ),
              ],
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
                    event?.title ?? LocaleService.current.tgCountdownEmpty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ps.wr('onSurface'),
                    ),
                  ),
                ),
                if (event != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ps.wr('tertiaryContainer'),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      ps.formatDayMonth(event.startDate).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: ps.wr('onTertiaryContainer'),
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                tile(
                  '${left.inDays}',
                  LocaleService.current.tgCountdownDays,
                  ps.wr('primaryContainer'),
                  ps.wr('onPrimaryContainer'),
                  ps.wr('onContainerSoft'),
                ),
                const SizedBox(width: 8),
                tile(
                  '${left.inHours % 24}',
                  LocaleService.current.tgCountdownHours,
                  ps.wr('surfaceContainer'),
                  ps.wr('onSurface'),
                  ps.wr('onSurfaceVariant'),
                ),
                const SizedBox(width: 8),
                tile(
                  '${left.inMinutes % 60}',
                  LocaleService.current.tgCountdownMinutes,
                  ps.wr('surfaceContainer'),
                  ps.wr('onSurface'),
                  ps.wr('onSurfaceVariant'),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 8,
                backgroundColor: ps.wr('trackOnSurface'),
                valueColor: AlwaysStoppedAnimation<Color>(ps.wr('primary')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Превью «Календарь лет» 2×2: сетка сверху, число снизу.
class YearGrid2x2Preview extends StatelessWidget {
  const YearGrid2x2Preview({
    super.key,
    required this.ps,
    required this.progress,
  });

  final PreviewStyle ps;
  final YearProgress? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;

    final p = progress;
    // Как и у 4×2: рисуем в дизайнерском квадрате и ужимаем целиком, иначе
    // сетка месяцев с числом не влезают в узкую карточку каталога.
    return AspectRatio(
      aspectRatio: 1,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 200,
          height: 200,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ps.wr('surface'),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: ps.wr('trackOnSurface')),
            ),
            child: p == null
                ? ps.emptyLabel(ps.wr('onSurfaceVariant'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ps.monthsGrid(p, dot: 8, gap: 4),
                      // Число дней растёт вместе с парой, и в тесном квадрате 2×2
                      // подпись под ним налезала на строку ниже (скриншот тестера,
                      // 13 августа 2026). Блок ужимается целиком, а не обрезается.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${p.daysTotal}',
                                style: TextStyle(
                                  fontSize: 52,
                                  height: 1.02,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -2.3,
                                  color: ps.wr('onSurface'),
                                ),
                              ),
                              Text(
                                LocaleService.current.tgYearDaysTogether(
                                  p.daysTotal,
                                ),
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: ps.wr('primary'),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                LocaleService.current.tgYearCurrentYearShort(
                                  p.yearsCompleted + 1,
                                  p.daysToNextAnniversary,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: ps.wr('onSurfaceVariant'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Превью «Календарь лет» 4×2: число и годы сверху, сетка и отсчёт снизу.
class YearGrid4x2Preview extends StatelessWidget {
  const YearGrid4x2Preview({
    super.key,
    required this.ps,
    required this.progress,
    required this.togetherStart,
  });

  final PreviewStyle ps;
  final YearProgress? progress;
  final DateTime? togetherStart;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final togetherStart = this.togetherStart;

    final p = progress;
    final start = togetherStart;

    // Кегли, сетка месяцев и плашка «до года» подобраны под ширину макета
    // (424). В каталоге карточка уже, и содержимое не ужималось, а
    // переполнялось: плашка наезжала на точки (снимок 20.09.2026). Рисуем в
    // дизайнерском размере и ужимаем картинку целиком, как превью «Вместе».
    return AspectRatio(
      aspectRatio: 424 / 200,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 424,
          height: 200,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: ps.wr('surface'),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: ps.wr('trackOnSurface')),
            ),
            child: p == null
                ? ps.emptyLabel(ps.wr('onSurfaceVariant'))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${p.daysTotal}',
                            style: TextStyle(
                              fontSize: 60,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2.8,
                              color: ps.wr('onSurface'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              LocaleService.current.tgYearDaysWord(p.daysTotal),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ps.wr('onSurfaceVariant'),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                LocaleService.current.tgYearsAndDays(
                                  p.yearsCompleted,
                                  p.daysIntoYear,
                                ),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: ps.wr('primary'),
                                ),
                              ),
                              if (start != null)
                                Text(
                                  LocaleService.current.tgYearSince(
                                    ps.formatDate(start),
                                  ),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: ps.wr('onSurfaceVariant'),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ps.monthsGrid(p, dot: 9, gap: 5),
                          const SizedBox(width: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: ps.wr('surfaceContainer'),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${p.daysToNextAnniversary}',
                                  style: TextStyle(
                                    fontSize: 22,
                                    height: 1.05,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                    color: ps.wr('primary'),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  LocaleService.current.tgYearToAnniversary(
                                    p.yearsCompleted + 1,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: ps.wr('onSurfaceVariant'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class YearRingPreview extends StatelessWidget {
  const YearRingPreview({
    super.key,
    required this.ps,
    required this.progress,
    required this.memoriesCount,
    required this.small,
  });

  final PreviewStyle ps;
  final YearProgress? progress;
  final int? memoriesCount;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final memoriesCount = this.memoriesCount;

    final p = progress;
    if (p == null) {
      return AspectRatio(
        aspectRatio: small
            ? 1
            : YearRingSpec.mediumWidth / YearRingSpec.mediumHeight,
        child: Container(
          decoration: BoxDecoration(
            color: ps.wr('primary'),
            borderRadius: BorderRadius.circular(22),
          ),
          child: ps.emptyLabel(ps.wr('onPrimarySoft')),
        ),
      );
    }
    final memories = memoriesCount ?? 0;
    return YearRingCard(
      small: small,
      colors: YearRingColors(
        primary: ps.wr('primary'),
        onPrimary: ps.wr('onPrimary'),
        tertiaryContainer: ps.wr('tertiaryContainer'),
      ),
      texts: YearRingTexts(
        daysCaption: small
            ? LocaleService.current.tgYearDaysWord(p.daysTotal)
            : LocaleService.current.tgYearDaysTogether(p.daysTotal),
        untilAnniversary: LocaleService.current.tgYearUntilAnniversary,
        daysLeftUnit: LocaleService.current.tgYearDaysUnit(
          p.daysToNextAnniversary,
        ),
        anniversaryLine: LocaleService.current.tgYearAnniversaryOn.replaceAll(
          '{date}',
          ps.formatDayMonth(p.nextAnniversary),
        ),
        monthsShort: LocaleService.current.tgYearMonthsShort,
        memoriesUnit: LocaleService.current.memoriesUnit(memories),
        smallLine: LocaleService.current.tgYearDaysLeft(
          p.daysToNextAnniversary,
        ),
      ),
      daysTotal: p.daysTotal,
      daysLeft: p.daysToNextAnniversary,
      months: p.monthsCompleted,
      memories: memories,
      progress: p.ringProgress,
    );
  }
}

/// Плитка нижнего ряда «Комнаты»: крупное число или полоса и подпись.
class MascotTile extends StatelessWidget {
  const MascotTile({
    super.key,
    required this.ps,
    this.value,
    this.child,
    required this.caption,
  });

  final PreviewStyle ps;
  final String? value;
  final Widget? child;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final child = this.child;
    return Container(
      decoration: BoxDecoration(
        color: ps.wr('primaryContainer'),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (value != null)
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: ps.wr('onPrimaryContainer'),
                ),
              ),
            ),
          if (child != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: child,
            ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Onest',
              fontWeight: FontWeight.w600,
              fontSize: 8.5,
              color: ps.wr('onSurfaceVariant'),
            ),
          ),
        ],
      ),
    );
  }
}
