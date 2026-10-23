import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/fork/e2e/banner_defer.dart';

void main() {
  testWidgets(
    'defer persists for a week and a new identity has a different scope',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final start = DateTime.utc(2026, 10, 23);
      Future<void> show(String scope, int days) async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ForkE2EBannerDefer(
                scope: scope,
                now: () => start.add(Duration(days: days)),
                builder: (later) =>
                    TextButton(onPressed: later, child: const Text('reminder')),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await show('old-identity', 0);
      await t.tap(find.text('reminder'));
      await t.pumpAndSettle();
      expect(find.text('reminder'), findsNothing);
      await show('old-identity', 6);
      expect(find.text('reminder'), findsNothing);
      await show('new-identity', 6);
      expect(find.text('reminder'), findsOneWidget);
      await show('old-identity', 8);
      expect(find.text('reminder'), findsOneWidget);
    },
  );
}
