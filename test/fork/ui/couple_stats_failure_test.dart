import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/couple_stats_screen.dart';
import 'package:love_app/theme/app_theme.dart';

void main() {
  testWidgets(
    'network failure is distinct from empty stats and retry forces reload',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CoupleStatsScreen(
            theme: AppThemes.pink,
            groupId: 'g',
            myUid: 'me',
            loadStats: (force) async {
              calls++;
              if (calls == 1) throw const SocketException('offline');
              expect(force, isTrue);
              return null;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining(RegExp('Пока нечего|Nothing to show')),
        findsNothing,
      );
      await t.tap(find.textContaining(RegExp('Повторить|Retry')));
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(
        find.textContaining(RegExp('Пока нечего|Nothing to show')),
        findsOneWidget,
      );
    },
  );
}
