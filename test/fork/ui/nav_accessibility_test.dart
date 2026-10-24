import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/home/home_bottom_nav.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('navigation at $width with large text has named actions', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final taps = <int>[];
      final s = LocaleService.current;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: Align(
          alignment: Alignment.bottomCenter,
          child: HomeBottomNav(
            selectedIndex: 0, theme: AppThemes.pink, isPaired: true,
            onTap: taps.add, onCreatePin: () {},
          ),
        )),
      ));
      expect(find.text(s.home), findsOneWidget);
      for (final label in [s.home, s.widgets, s.watchTogether, s.connect, s.profile]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.hasFlag(SemanticsFlag.isSelected), label == s.home);
      }
      await tester.tap(find.byTooltip(s.profile));
      await tester.pumpAndSettle();
      expect(taps, [3]);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
