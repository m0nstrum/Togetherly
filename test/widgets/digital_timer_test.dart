// D7: цифровой вид таймера на главной.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/timer_parts.dart';
import 'package:love_app/widgets/digital_timer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TimerParts', () {
    test('календарные годы, месяцы и дни, время суток, всего дней', () {
      final p = TimerParts.of(DateTime(2023, 1, 31, 10), DateTime(2024, 3, 1, 12, 5, 7));
      expect([p.years, p.months, p.days], [1, 1, 1]);
      expect(p.clock, '02:05:07');
      expect(p.totalDays, 395);
    });

    test('края месяцев: без отрицательных дней', () {
      final cases = {
        (DateTime(2024, 1, 31), DateTime(2024, 3, 1)): [0, 1, 1],
        // Конец месяца к концу месяца — ровно месяц.
        (DateTime(2024, 1, 31), DateTime(2024, 2, 29)): [0, 1, 0],
        (DateTime(2023, 5, 31, 23), DateTime(2023, 6, 30, 22)): [0, 0, 29],
        (DateTime(2020, 2, 29), DateTime(2021, 2, 28)): [1, 0, 0],
        (DateTime(2020, 2, 29), DateTime(2021, 3, 1)): [1, 0, 1],
      };
      cases.forEach((k, want) {
        final p = TimerParts.of(k.$1, k.$2);
        expect([p.years, p.months, p.days], want, reason: '$k');
      });
      // Перебор: дни всегда в пределах месяца.
      var d = DateTime(2023, 1, 1);
      for (var i = 0; i < 800; i++) {
        final p = TimerParts.of(DateTime(2022, 1, 31, 12), d);
        expect(p.days, inInclusiveRange(0, 30), reason: '$d');
        expect(p.months, inInclusiveRange(0, 11), reason: '$d');
        d = d.add(const Duration(hours: 13));
      }
    });

    test('обратный отсчёт и прошедшая дата — нули', () {
      final now = DateTime(2026, 10, 25);
      final p = TimerParts.of(DateTime(2026, 10, 27, 1), now, countdown: true);
      expect(p.totalDays, 2);
      expect(p.hours, 1);
      expect(identical(TimerParts.of(DateTime(2026, 10, 1), now, countdown: true), TimerParts.zero), isTrue);
      expect(identical(TimerParts.of(DateTime(2027, 1, 1), now), TimerParts.zero), isTrue);
    });
  });

  testWidgets('цифры: дни вместе, части и касание по дням', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            height: 340,
            child: DigitalTimer(
              theme: AppThemes.all.first,
              startDate: DateTime(2022, 5, 1),
              now: () => DateTime(2025, 6, 3, 4, 5, 6),
              onPartTap: (l) => tapped = l,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('04:05:06'), findsOneWidget);
    expect(find.text('1 129'), findsOneWidget);
    await tester.tap(find.text('2'));
    expect(tapped, LocaleService.current.daysShortLabel);
  });

  test('выбор вида помнится', () async {
    SharedPreferences.setMockInitialValues({});
    expect(TimerViewPref.digital.value, isFalse);
    await TimerViewPref.toggle();
    expect(TimerViewPref.digital.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('home_timer_digital'), isTrue);
    await TimerViewPref.toggle();
  });
}
