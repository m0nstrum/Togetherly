import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/app_lock/app_lock.dart';
import 'package:love_app/fork/secure_screen.dart';
import 'package:love_app/fork/app_lock/app_lock_ui.dart';

class Device implements ForkLockPlatform {
  bool secured = true, success = true, failProtection = false;
  int prompts = 0;
  final protection = <bool>[];
  Completer<bool>? challenge;
  @override
  Future<bool> available() async => secured;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return challenge?.future ?? success;
  }

  @override
  Future<void> protect(bool value) async {
    if (failProtection) throw StateError('window unavailable');
    protection.add(value);
  }

  @override
  Future<void> openSettings() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Device device;
  late ForkAppLock lock;
  late bool saved;
  setUp(() {
    device = Device();
    saved = false;
    lock = ForkAppLock(
      platform: device,
      read: () async => saved,
      write: (value) async {
        saved = value;
      },
    );
  });
  tearDown(() => lock.dispose());

  test(
    'default off does not prompt or protect; saved on blocks at startup',
    () async {
      expect(lock.blocked, isTrue);
      await lock.load();
      expect(lock.blocked, isFalse);
      expect(device.protection, isEmpty);
      expect(device.prompts, 0);
      final startup = ForkAppLock(
        platform: device,
        read: () async => true,
        write: (_) async {},
      );
      await startup.load();
      expect(startup.enabled, isTrue);
      expect(startup.blocked, isTrue);
      expect(device.protection, [true]);
      startup.dispose();
    },
  );

  test('cancel or missing device PIN cannot enable protection', () async {
    await lock.load();
    device.success = false;
    expect(await lock.setEnabled(true, 'enable'), isFalse);
    expect(saved, isFalse);
    expect(device.protection, isEmpty);
    device.secured = false;
    expect(await lock.setEnabled(true, 'enable'), isFalse);
    expect(lock.problem, ForkLockProblem.deviceNotSecured);
  });

  test(
    'background requires a new check; inactive only covers temporarily',
    () async {
      await lock.load();
      await lock.setEnabled(true, 'enable');
      expect(saved, isTrue);
      expect(lock.blocked, isFalse);
      lock.inactive();
      expect(lock.blocked, isTrue);
      lock.resumed();
      expect(lock.blocked, isFalse);
      lock.background();
      lock.resumed();
      expect(lock.blocked, isTrue);
      device.success = false;
      expect(await lock.unlock('unlock'), isFalse);
      expect(lock.blocked, isTrue);
      device.success = true;
      expect(await lock.unlock('unlock'), isTrue);
      expect(lock.blocked, isFalse);
    },
  );

  test('grace period keeps short trips unlocked and is persisted', () async {
    var now = DateTime.utc(2026, 10, 24, 12);
    var stored = 0;
    final graced = ForkAppLock(
      platform: device,
      read: () async => saved,
      write: (value) async {
        saved = value;
      },
      readGrace: () async => stored,
      writeGrace: (value) async {
        stored = value;
      },
      clock: () => now,
    );
    addTearDown(graced.dispose);
    await graced.load();
    await graced.setEnabled(true, 'enable');
    expect(await graced.setGrace(const Duration(minutes: 7), 'x'), isFalse);
    final prompts = device.prompts;
    expect(await graced.setGrace(const Duration(minutes: 10), 'x'), isTrue);
    expect(device.prompts, prompts + 1, reason: 'longer grace asks first');
    expect(stored, 600);

    graced.background();
    expect(graced.blocked, isTrue, reason: 'recents preview stays covered');
    now = now.add(const Duration(minutes: 9));
    graced.resumed();
    expect(graced.blocked, isFalse);

    graced.background();
    now = now.add(const Duration(minutes: 10));
    graced.resumed();
    expect(graced.blocked, isTrue);
    await graced.unlock('unlock');

    graced.background();
    now = now.subtract(const Duration(minutes: 1));
    graced.resumed();
    expect(graced.blocked, isTrue, reason: 'clock moved back');
    await graced.unlock('unlock');

    expect(await graced.setGrace(Duration.zero, 'x'), isTrue);
    graced.background();
    graced.resumed();
    expect(graced.blocked, isTrue);

    stored = 12345;
    final reloaded = ForkAppLock(
      platform: device,
      read: () async => true,
      write: (_) async {},
      readGrace: () async => stored,
    );
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.grace, Duration.zero, reason: 'unknown value → strictest');
  });

  test(
    'disabling requires authentication and releases only after persistence',
    () async {
      await lock.load();
      await lock.setEnabled(true, 'enable');
      device.success = false;
      expect(await lock.setEnabled(false, 'disable'), isFalse);
      expect(lock.enabled, isTrue);
      expect(saved, isTrue);
      expect(device.protection, [true]);
      device.success = true;
      expect(await lock.setEnabled(false, 'disable'), isTrue);
      expect(saved, isFalse);
      expect(device.protection, [true, false]);
    },
  );

  test('cannot start a second prompt while first is in progress', () async {
    await lock.load();
    device.challenge = Completer<bool>();
    final enabling = lock.setEnabled(true, 'enable');
    await Future<void>.delayed(Duration.zero);
    expect(await lock.setEnabled(true, 'enable'), isFalse);
    expect(device.prompts, 1);
    device.challenge!.complete(true);
    expect(await enabling, isTrue);
  });

  test('failed preference save rolls back new protection', () async {
    lock.dispose();
    device.protection.clear();
    lock = ForkAppLock(
      platform: device,
      read: () async => false,
      write: (_) async => throw StateError('disk full'),
    );
    await lock.load();
    expect(await lock.setEnabled(true, 'enable'), isFalse);
    expect(lock.enabled, isFalse);
    expect(device.protection, [true, false]);
  });

  test(
    'unreadable preference fails closed and can retry even after sync throw',
    () async {
      lock.dispose();
      var broken = true;
      lock = ForkAppLock(
        platform: device,
        read: () {
          if (broken) throw StateError('corrupt preferences');
          return Future.value(true);
        },
        write: (_) async {},
      );
      await lock.load();
      expect(lock.blocked, isTrue);
      expect(lock.ready, isFalse);
      broken = false;
      await lock.load();
      expect(lock.ready, isTrue);
      expect(lock.enabled, isTrue);
      expect(lock.blocked, isTrue);
    },
  );

  test(
    'failed recents protection never exposes a configured locked app',
    () async {
      saved = true;
      device.failProtection = true;
      await lock.load();
      expect(lock.ready, isFalse);
      expect(lock.blocked, isTrue);
      device.failProtection = false;
      await lock.load();
      expect(lock.ready, isTrue);
      expect(lock.blocked, isTrue);
    },
  );

  testWidgets(
    'gate hides private route through inactive, background and resume',
    (tester) async {
      saved = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ForkAppLockGate(
            controller: lock,
            child: const Scaffold(body: Text('private route and dialog')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('private route and dialog'), findsNothing);
      await lock.unlock('unlock');
      await tester.pumpAndSettle();
      expect(find.text('private route and dialog'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('private route and dialog'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('private route and dialog'), findsNothing);
      await lock.unlock('unlock');
      await tester.pumpAndSettle();
      expect(find.text('private route and dialog'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('root gate also hides an already opened Navigator dialog', (
    tester,
  ) async {
    await lock.load();
    await lock.setEnabled(true, 'enable');
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) =>
            ForkAppLockGate(controller: lock, child: child!),
        home: const Scaffold(body: Text('private home')),
      ),
    );
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('private dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('private dialog'), findsOneWidget);
    lock.background();
    await tester.pump();
    expect(find.text('private dialog'), findsNothing);
    await lock.unlock('unlock');
    lock.resumed();
    await tester.pumpAndSettle();
    expect(find.text('private dialog'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'old Android protection can retry and respects a simultaneous secret route',
    () async {
      const channel = MethodChannel('tethered/app_lock');
      const secure = MethodChannel('tethered/screen_security');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var failing = true;
      final flags = <bool>[];
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      messenger.setMockMethodCallHandler(secure, (call) async {
        if (call.arguments == true && failing) {
          throw PlatformException(code: 'window');
        }
        flags.add(call.arguments as bool);
        return null;
      });
      final platform = ForkNativeLock();
      try {
        await expectLater(
          platform.protect(true),
          throwsA(isA<PlatformException>()),
        );
        failing = false;
        await platform.protect(true);
        final secret = await ForkScreenSecurity.acquire();
        flags.clear();
        await platform.protect(false);
        expect(flags, isEmpty);
        await secret.release();
        expect(flags, [false]);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(secure, null);
      }
    },
  );

  for (final modern in [true, false]) {
    test(
      'native recents protection uses ${modern ? 'modern API' : 'FLAG_SECURE fallback'}',
      () async {
        final calls = <String>[];
        const channel = MethodChannel('tethered/app_lock');
        const secure = MethodChannel('tethered/screen_security');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add('${call.method}:${call.arguments}');
          return modern;
        });
        messenger.setMockMethodCallHandler(secure, (call) async {
          calls.add('secure:${call.arguments}');
          return null;
        });
        try {
          final platform = ForkNativeLock();
          await platform.protect(true);
          await platform.protect(false);
          expect(
            calls,
            modern
                ? ['setRecentsProtected:true', 'setRecentsProtected:false']
                : [
                    'setRecentsProtected:true',
                    'secure:true',
                    'setRecentsProtected:false',
                    'secure:false',
                  ],
          );
        } finally {
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(secure, null);
        }
      },
    );
  }
}
