import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/fork/battery/battery_share.dart';
import 'package:love_app/services/pocketbase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'logout while battery start awaits preferences does not restart sampling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final battery = ForkBattery.instance;
      final originalRead = battery.read;
      addTearDown(() {
        battery.stop();
        battery.read = originalRead;
      });
      var reads = 0;
      battery.read = () async {
        reads++;
        return (80, false);
      };
      final starting = battery.start('pair', 'alice');
      PocketBaseService().signOut();
      await starting;
      await tester.pump();
      expect(reads, 0);
      // testWidgets also detects a leaked periodic timer here.
    },
  );

  test('logout discards a battery read already in progress', () async {
    final battery = ForkBattery.instance;
    final originalRead = battery.read;
    final originalPrint = debugPrint;
    addTearDown(() {
      battery.stop();
      battery.read = originalRead;
      debugPrint = originalPrint;
    });
    final reading = Completer<(int, bool)?>();
    final entered = Completer<void>();
    final logs = <String?>[];
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    battery.read = () {
      entered.complete();
      return reading.future;
    };
    final reporting = battery.report(
      groupId: 'old-pair',
      uid: 'alice',
      force: true,
    );
    await entered.future;
    PocketBaseService().signOut();
    reading.complete((70, false));
    await reporting;
    // Attempting the write after logout would touch uninitialized PB and log it.
    expect(
      logs.where((line) => line?.contains('ForkBattery') ?? false),
      isEmpty,
    );
  });
}
