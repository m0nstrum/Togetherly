import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/home_defaults.dart';
import 'package:love_app/fork/profile/partner_page.dart';
import 'package:love_app/models/home_layout.dart';
import 'package:love_app/theme/app_theme.dart';

/// Профиль партнёра не пустой (просьба владельца 22.10).
void main() {
  Future<void> pump(WidgetTester t, ForkPartnerFacts f, {int? days}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ForkPartnerPage(
            theme: AppThemes.pink,
            groupId: 'g1',
            partnerUid: 'u2',
            partnerName: 'Аня',
            daysTogether: days,
            facts: f,
            live: false,
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('ничего не известно — действия и «Общее», без пустых блоков', (t) async {
    await pump(t, const ForkPartnerFacts());
    for (final k in ['fork-partner-call', 'fork-partner-miss', 'fork-partner-watch', 'fork-partner-map']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.byIcon(Icons.cake_outlined), findsNothing);
    expect(find.byKey(const ValueKey('fork-partner-stats')), findsNothing, reason: 'нет цифр — нет плиток');
    expect(find.byIcon(Icons.manage_search_rounded), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('известное — видно: статус, музыка, день рождения, пара в цифрах', (t) async {
    final now = DateTime.now();
    await pump(
      t,
      ForkPartnerFacts(
        status: 'на работе до 7',
        music: 'Земфира — Искала',
        birthday: DateTime(1999, now.month, now.day).add(const Duration(days: 3)),
        memories: 42,
        messages: 1500,
        wishes: 3,
      ),
      days: 365,
    );
    expect(find.text('на работе до 7'), findsOneWidget);
    expect(find.text('Земфира — Искала'), findsOneWidget);
    expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('365'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'желаний партнёра');
  });

  test('день рождения и местное время', () {
    final now = DateTime(2026, 10, 22, 12);
    expect(ForkPartnerFacts.daysToBirthday(DateTime(1999, 10, 22), now), 0);
    expect(ForkPartnerFacts.daysToBirthday(DateTime(1999, 10, 25), now), 3);
    expect(ForkPartnerFacts.daysToBirthday(DateTime(1999, 10, 21), now), 364);
    expect(ForkPartnerFacts(zone: now.timeZoneOffset).localTime(now), isNull, reason: 'тот же пояс');
    final other = now.timeZoneOffset + const Duration(hours: 5);
    expect(ForkPartnerFacts(zone: other).localTime(now)!.hour, now.toUtc().add(other).hour);
  });

  test('главная форка: сундук и задания спрятаны, остальное на месте', () {
    expect(ForkHome.layout.showsBlock(HomeBlock.chest), isFalse);
    expect(ForkHome.layout.showsBlock(HomeBlock.tasks), isFalse);
    expect(ForkHome.layout.visibleBlocks, [HomeBlock.mascot, HomeBlock.map, HomeBlock.wishes, HomeBlock.lane]);
    expect(ForkHome.isDefault(ForkHome.layout), isTrue);
    expect(ForkHome.isDefault(ForkHome.layout.withBlock(HomeBlock.chest, shown: true)), isFalse);
  });
}

