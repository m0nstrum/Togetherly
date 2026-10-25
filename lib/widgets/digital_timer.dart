import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dict_strings.dart' show ruEn;
import '../fork/l10n/count_words.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../utils/readable_text.dart';
import '../utils/timer_parts.dart';

/// Вид таймера на главной: круг с лепестками или цифры (BACKLOG D7).
///
/// Выбор свой у каждого телефона и помнится между запусками.
abstract final class TimerViewPref {
  static const _key = 'home_timer_digital';

  /// true — цифры.
  static final ValueNotifier<bool> digital = ValueNotifier(false);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      digital.value = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Без настроек — круг, как раньше.
    }
  }

  static Future<void> toggle() async {
    digital.value = !digital.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, digital.value);
    } catch (_) {}
  }
}

/// Цифровой таймер: «1 234 дня», под ним годы-месяцы-дни и часы:минуты:секунды.
///
/// Касание по дням или месяцам ведёт туда же, куда лепестки круга,
/// ([onPartTap] получает ту же подпись, что лепесток).
class DigitalTimer extends StatefulWidget {
  const DigitalTimer({
    super.key,
    required this.theme,
    required this.startDate,
    this.isCountdown = false,
    this.onPartTap,
    @visibleForTesting this.now,
  });

  final AppTheme theme;
  final DateTime startDate;
  final bool isCountdown;
  final ValueChanged<String>? onPartTap;

  /// Часы для тестов.
  final DateTime Function()? now;

  @override
  State<DigitalTimer> createState() => _DigitalTimerState();
}

class _DigitalTimerState extends State<DigitalTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Перестраивается только сам таймер, раз в секунду.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final now = (widget.now ?? DateTime.now)();
    final p = TimerParts.of(widget.startDate, now, countdown: widget.isCountdown);
    final ink = readableTextOn(t.timerDialBackground);
    final l = LocaleService.current;

    Widget part(int value, String label, {bool tappable = false}) {
      final child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              style: AppFonts.unbounded(size: 22, weight: 700, color: ink)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text(label, style: AppFonts.onest(size: 12, weight: 600, color: ink.withValues(alpha: 0.75))),
          ],
        ),
      );
      final tap = widget.onPartTap;
      if (!tappable || tap == null) return child;
      return Semantics(
        button: true,
        label: '$value $label',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            tap(label);
          },
          child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48), child: child),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.timerDialBackground,
        borderRadius: BorderRadius.circular(36),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: false,
              label: widget.isCountdown
                  ? ruEn('Осталось ${p.totalDays} ${forkDaysWord(p.totalDays)}', '${p.totalDays} ${forkDaysWord(p.totalDays)} left')
                  : ruEn('Вместе ${p.totalDays} ${forkDaysWord(p.totalDays)}', 'Together ${p.totalDays} ${forkDaysWord(p.totalDays)}'),
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(
                    _grouped(p.totalDays),
                    style: AppFonts.unbounded(size: 56, weight: 800, color: ink, height: 1.05)
                        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  Text(
                    widget.isCountdown
                        ? ruEn('${forkDaysWord(p.totalDays)} осталось', '${forkDaysWord(p.totalDays)} left')
                        : ruEn('${forkDaysWord(p.totalDays)} вместе', '${forkDaysWord(p.totalDays)} together'),
                    style: AppFonts.onest(size: 15, weight: 600, color: ink.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                part(p.years, l.yearsLabel),
                part(p.months, l.monthsShortLabel, tappable: true),
                part(p.days, l.daysShortLabel, tappable: true),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.clock,
              style: AppFonts.unbounded(size: 30, weight: 600, color: ink)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    );
  }

  /// «1 234» — тысячи через узкий пробел.
  static String _grouped(int n) {
    final s = '$n';
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
      out.write(s[i]);
    }
    return out.toString();
  }
}
