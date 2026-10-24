import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/quick_tiles.dart';
import 'package:love_app/services/deep_link_service.dart';

void main() {
  const channel = MethodChannel('tethered/quick_tiles');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  bool? enabled;
  bool failing = false;
  Completer<void>? setting;
  setUp(() {
    enabled = false;
    failing = false;
    setting = null;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'getEnabled') return enabled;
      if (failing) throw PlatformException(code: 'unavailable');
      if (setting != null) await setting!.future;
      enabled = call.arguments as bool;
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ForkQuickTilesSettings())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'OS default off; switch changes only after native acknowledgement',
    (tester) async {
      await show(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(calls.map((call) => call.method), ['getEnabled']);
      setting = Completer<void>();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      setting!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      setting = null;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        calls
            .where((call) => call.method == 'setEnabled')
            .map((call) => call.arguments),
        [true, false],
      );
    },
  );

  testWidgets(
    'native failure keeps previous state and offers a state refresh',
    (tester) async {
      await show(tester);
      failing = true;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      final retry = find.byType(TextButton);
      expect(retry, findsOneWidget);
      failing = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    },
  );

  testWidgets('old Android hides unsupported tiles', (tester) async {
    enabled = null;
    await show(tester);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('other platforms do not call Android channels', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await show(tester);
      expect(find.byType(Switch), findsNothing);
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'tile deep links are safe screen destinations, distinct from instant miss',
    () {
      expect(
        DeepLinkService.isWidgetAction(Uri.parse('loveapp://fork-miss')),
        isTrue,
      );
      expect(
        DeepLinkService.isWidgetAction(Uri.parse('loveapp://touch')),
        isTrue,
      );
      expect(
        DeepLinkService.isWidgetAction(Uri.parse('https://touch')),
        isFalse,
      );
    },
  );
}
