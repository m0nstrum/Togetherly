import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/battery/battery_share.dart';
import 'package:love_app/fork/battery/battery_ui.dart';

void main() {
  testWidgets('chat badge expires after an hour without a new server event', (
    t,
  ) async {
    final at = DateTime(2026, 10, 23, 12);
    var now = at.add(const Duration(minutes: 59));
    final state = ForkBatteryState(level: 5, charging: false, at: at);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForkBatteryBadge(
            groupId: 'g',
            uid: 'p',
            color: Colors.grey,
            states: () => Stream.value(state),
            now: () => now,
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.text('5%'), findsOneWidget);
    expect(find.byTooltip(RegExp('59')), findsOneWidget);
    now = at.add(const Duration(hours: 1));
    await t.pump(const Duration(minutes: 1));
    expect(find.text('5%'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
