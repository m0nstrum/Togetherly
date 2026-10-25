// Волна 2 UX, навигация (UX_AUDIT.md: N5, N11, N12, N13).
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/connection.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/screens/home/home_header.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/profile_theme.dart';

Widget _header(
  AppTheme theme, {
  required bool paired,
  ValueChanged<int>? onOpenTab,
}) => MaterialApp(
  theme: ProfileTheme.themeFor(theme),
  home: Scaffold(
    body: HomeHeader(
      theme: theme,
      isPaired: paired,
      myAvatarUrl: '',
      myDisplayName: 'Саша',
      partners: paired
          ? const [GroupMember(uid: 'p1', name: 'Кристина', avatar: '')]
          : const [],
      myMood: const MemberMood(),
      moodOf: (_) => const MemberMood(),
      statusBadgeText: paired ? 'Встречаемся' : 'Не в паре',
      statusBadgeEmoji: '',
      pairId: '',
      onOpenTab: onOpenTab,
    ),
  ),
);

void main() {
  final theme = AppThemes.pink;

  testWidgets('relationship pill exposes a named TalkBack button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final tabs = <int>[];
    await tester.pumpWidget(_header(theme, paired: false, onOpenTab: tabs.add));
    final finder = find.bySemanticsLabel(
      RegExp('Тип связи:|Relationship type:'),
    );
    final node = tester.getSemantics(finder);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(finder);
    expect(tabs, [2]);
    semantics.dispose();
  });

  testWidgets('N13: «Не в паре» ведёт на вкладку «Связь»', (tester) async {
    final tabs = <int>[];
    await tester.pumpWidget(_header(theme, paired: false, onOpenTab: tabs.add));
    await tester.tap(find.text('Не в паре'));
    expect(tabs, [2]);
  });

  testWidgets('N13: без обработчика пилюля остаётся неактивной', (
    tester,
  ) async {
    await tester.pumpWidget(_header(theme, paired: false));
    await tester.tap(find.text('Не в паре'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'N5: тап по своему аватару (даже с заглушкой) открывает профиль',
    (tester) async {
      final tabs = <int>[];
      await tester.pumpWidget(
        _header(theme, paired: false, onOpenTab: tabs.add),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('Мой профиль|My profile')));
      expect(tabs, [3]);
    },
  );

  testWidgets('N5: у аватара партнёра есть подпись «Профиль»', (tester) async {
    await tester.pumpWidget(_header(theme, paired: true));
    expect(
      find.bySemanticsLabel(RegExp('Профиль: Кристина|Profile: Кристина')),
      findsOneWidget,
    );
  });

  testWidgets('N11: у круглой кнопки есть подпись и подсказка', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HomeBottomNav(
              selectedIndex: 0,
              theme: theme,
              isPaired: true,
              onTap: (_) {},
              onCreatePin: () {},
              sideIsArrow: true,
              onSideLongPress: () {},
            ),
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byTooltip(RegExp('.+')).last);
    expect(node.label, isNotEmpty);
    handle.dispose();
  });
}
