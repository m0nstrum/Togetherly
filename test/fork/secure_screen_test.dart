import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/secure_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tethered/screen_security');
  late List<bool> calls;
  setUp(() {
    calls = [];
  });
  void native(Future<void> Function(bool) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'setSecure');
          final secure = call.arguments as bool;
          calls.add(secure);
          await handler(secure);
          return null;
        });
  }

  Widget screen() => MaterialApp(
    home: ForkSecureScreen(
      builder: (_) => const Scaffold(body: Text('recovery phrase')),
    ),
  );

  testWidgets('phrase stays hidden until Android acknowledges protection', (
    tester,
  ) async {
    final ack = Completer<void>();
    native((secure) async {
      if (secure) await ack.future;
    });
    await tester.pumpWidget(screen());
    expect(find.text('recovery phrase'), findsNothing);
    ack.complete();
    await tester.pumpAndSettle();
    expect(find.text('recovery phrase'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });

  testWidgets('leaving before platform acknowledgement releases protection', (
    tester,
  ) async {
    final ack = Completer<void>();
    native((secure) async {
      if (secure) await ack.future;
    });
    await tester.pumpWidget(screen());
    await tester.pumpWidget(const SizedBox());
    ack.complete();
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
    expect(find.text('recovery phrase'), findsNothing);
  });

  test(
    'overlapping routes keep FLAG_SECURE until the last lease closes',
    () async {
      native((_) async {});
      final a = await ForkScreenSecurity.acquire();
      final b = await ForkScreenSecurity.acquire();
      await a.release();
      expect(calls, [true, true]);
      await b.release();
      await b.release();
      expect(calls, [true, true, false]);
    },
  );

  testWidgets('platform failure hides secrets and allows a retry', (
    tester,
  ) async {
    var fail = true;
    native((secure) async {
      if (secure && fail) throw PlatformException(code: 'failed');
    });
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('recovery phrase'), findsNothing);
    fail = false;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('recovery phrase'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls.last, isFalse);
  });
}
