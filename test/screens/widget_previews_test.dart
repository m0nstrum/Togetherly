// A12-1, часть 2: превью каталога виджетов вынесены из экрана, данные экрана
// приходят параметрами. Здесь — что превью показывают по этим данным.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/pair_data.dart';
import 'package:love_app/models/timer_item.dart';
import 'package:love_app/models/year_progress.dart';
import 'package:love_app/screens/widget_screen/preview_style.dart';
import 'package:love_app/screens/widget_screen/previews_pair.dart';
import 'package:love_app/screens/widget_screen/previews_time.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/services/timer_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/services/widget_theme_sync.dart';

void main() {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4));
  final ps = PreviewStyle(cs);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async => LocaleService.instance.setLanguage(AppLanguage.en));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );

  group('PreviewStyle', () {
    test('цвета — те же роли, что уходят в нативные виджеты', () {
      final roles = WidgetThemeSync.rolesOf(cs);
      expect(ps.wr('primary'), roles['primary']);
      expect(ps.wr('нет такой роли'), cs.primary);
    });

    test('день и месяц — по языку приложения', () async {
      final d = DateTime(2026, 2, 14);
      await LocaleService.instance.setLanguage(AppLanguage.ru);
      expect(ps.formatDayMonth(d), '14 февраля');
      await LocaleService.instance.setLanguage(AppLanguage.en);
      expect(ps.formatDayMonth(d), 'Feb 14');
    });

    test('дата цифрами и инициал', () {
      expect(ps.formatDate(DateTime(2020, 9, 3)), '03.09.2020');
      expect(ps.initialOf('  анна'), 'А');
      expect(ps.initialOf('   '), '');
    });
  });

  group('превью', () {
    testWidgets('без даты начала годовые превью просят её указать', (
      tester,
    ) async {
      final empty = LocaleService.current.tgYearNoStartDate;
      for (final w in <Widget>[
        YearGrid2x2Preview(ps: ps, progress: null),
        YearGrid4x2Preview(ps: ps, progress: null, togetherStart: null),
        YearRingPreview(ps: ps, progress: null, memoriesCount: 3, small: true),
      ]) {
        await pump(tester, w);
        expect(find.text(empty), findsOneWidget, reason: '${w.runtimeType}');
      }
    });

    testWidgets('с датой начала — сетка лет вместо подписи', (tester) async {
      final p = YearProgress.between(
        DateTime(2020, 1, 1),
        DateTime(2026, 6, 1),
      );
      await pump(tester, YearGrid2x2Preview(ps: ps, progress: p));
      expect(find.text(LocaleService.current.tgYearNoStartDate), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('«До встречи» считает дни до ближайшего события', (
      tester,
    ) async {
      await pump(tester, Countdown2x2Preview(ps: ps, nextEvent: null));
      expect(find.text('—'), findsOneWidget);
      expect(find.text(LocaleService.current.tgCountdownEmpty), findsOneWidget);

      final event = TimerItem(
        id: 't1',
        title: 'Отпуск',
        startDate: DateTime.now().add(const Duration(days: 10, hours: 1)),
        isCountdown: true,
      );
      await pump(tester, Countdown2x2Preview(ps: ps, nextEvent: event));
      expect(find.text('10'), findsOneWidget);
      expect(find.textContaining('Отпуск'), findsOneWidget);
    });
    testWidgets('статистика пары — числа экрана, пустые — нулём', (
      tester,
    ) async {
      final t = buildAppTheme(kPalettes[0], Brightness.light);
      Widget stats({int? memories, int? drawings, int? miss}) =>
          RelationshipStatsPreview(
            t: t,
            drawingsCount: drawings,
            memoriesCount: memories,
            missYouCount: miss,
            pair: PairData(),
            timerService: TimerService(),
          );
      await pump(tester, stats(memories: 7, drawings: 3, miss: 12));
      for (final v in ['7', '3', '12']) {
        expect(find.text(v), findsOneWidget, reason: v);
      }
      await pump(tester, stats());
      expect(find.text('0'), findsNWidgets(4), reason: 'дни и три счётчика');
    });

    testWidgets('лепестковый таймер без таймера не падает', (tester) async {
      final t = buildAppTheme(kPalettes[0], Brightness.light);
      await pump(tester, PetalTimerPreview(t: t, widgetTimer: null));
      expect(tester.takeException(), isNull);
    });
  });
}
