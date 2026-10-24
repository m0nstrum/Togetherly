/// Opt-in device authentication, with protection independent of secret routes.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../secure_screen.dart';

abstract interface class ForkLockPlatform {
  Future<bool> available();
  Future<bool> authenticate(String reason);
  Future<void> protect(bool enabled);
  Future<void> openSettings();
}

class ForkNativeLock implements ForkLockPlatform {
  static const _channel = MethodChannel('tethered/app_lock');
  Future<ForkScreenLease>? _protection;
  @override
  Future<bool> available() async =>
      await _channel.invokeMethod<bool>('available') ?? false;
  @override
  Future<bool> authenticate(String reason) async =>
      await _channel.invokeMethod<bool>('authenticate', {'reason': reason}) ??
      false;
  @override
  Future<void> protect(bool enabled) async {
    final handled =
        await _channel.invokeMethod<bool>('setRecentsProtected', enabled) ??
        false;
    if (enabled && !handled) {
      final pending = _protection ??= ForkScreenSecurity.acquire();
      try {
        await pending;
      } catch (_) {
        if (identical(_protection, pending)) _protection = null;
        rethrow;
      }
    } else if (!enabled) {
      final lease = _protection;
      _protection = null;
      if (lease != null) await (await lease).release();
    }
  }

  @override
  Future<void> openSettings() =>
      _channel.invokeMethod<void>('securitySettings');
}

enum ForkLockProblem { deviceNotSecured, unavailable }

class ForkAppLock extends ChangeNotifier {
  ForkAppLock({
    required this.platform,
    required this.read,
    required this.write,
    Future<int> Function()? readGrace,
    Future<void> Function(int)? writeGrace,
    DateTime Function()? clock,
  }) : readGrace = readGrace ?? (() async => 0),
       writeGrace = writeGrace ?? ((_) async {}),
       clock = clock ?? DateTime.now;
  static const prefKey = 'fork.app_lock.enabled';
  static const gracePrefKey = 'fork.app_lock.grace_seconds';

  /// Choices for "lock after": immediately, 1 min, 10 min, 1 hour.
  static const graceChoices = <Duration>[
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 10),
    Duration(hours: 1),
  ];
  static final instance = ForkAppLock(
    platform: ForkNativeLock(),
    read: () async =>
        (await SharedPreferences.getInstance()).getBool(prefKey) ?? false,
    write: (value) async {
      if (!await (await SharedPreferences.getInstance()).setBool(
        prefKey,
        value,
      )) {
        throw StateError('Lock preference could not be saved');
      }
    },
    readGrace: () async =>
        (await SharedPreferences.getInstance()).getInt(gracePrefKey) ?? 0,
    writeGrace: (seconds) async {
      if (!await (await SharedPreferences.getInstance()).setInt(
        gracePrefKey,
        seconds,
      )) {
        throw StateError('Lock preference could not be saved');
      }
    },
  );

  final ForkLockPlatform platform;
  final Future<bool> Function() read;
  final Future<void> Function(bool) write;
  final Future<int> Function() readGrace;
  final Future<void> Function(int) writeGrace;
  final DateTime Function() clock;

  /// How long the app may stay in the background before it locks again.
  Duration grace = Duration.zero;
  DateTime? _hiddenAt;
  bool ready = false;
  bool enabled = false;
  bool locked = true;
  bool covered = false;
  bool busy = false;
  ForkLockProblem? problem;
  Future<void>? _loading;
  bool _disposed = false;
  bool get blocked => !ready || (enabled && (locked || covered));

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> load() {
    if (_loading != null) return _loading!;
    final future = Future<void>.sync(_load);
    _loading = future;
    unawaited(
      future.then((_) {
        if (!ready) _loading = null;
      }),
    );
    return future;
  }

  Future<void> _load() async {
    try {
      final saved = await read();
      final seconds = await readGrace();
      grace = Duration(
        seconds: graceChoices.any((d) => d.inSeconds == seconds) ? seconds : 0,
      );
      if (saved) await platform.protect(true);
      enabled = saved;
      locked = saved;
      ready = true;
      problem = null;
    } catch (_) {
      ready = false; // Unknown settings must never mean "lock off".
      problem = ForkLockProblem.unavailable;
    }
    notifyListeners();
  }

  void inactive() {
    if (enabled) {
      covered = true;
      notifyListeners();
    }
  }

  void background() {
    if (enabled) {
      covered = true;
      // The first hide counts: paused/hidden/detached arrive in a row.
      _hiddenAt ??= clock();
      if (grace == Duration.zero) locked = true;
      notifyListeners();
    }
  }

  void resumed() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // A clock moved backwards is treated as an expired grace.
    if (enabled && hiddenAt != null) {
      final away = clock().difference(hiddenAt);
      if (away.isNegative || away >= grace) locked = true;
    }
    covered = false;
    notifyListeners();
  }

  /// Changing the grace period needs the same check as turning the lock off.
  Future<bool> setGrace(Duration value, String reason) async {
    if (!ready || busy || value == grace) return false;
    if (!graceChoices.contains(value)) return false;
    busy = true;
    problem = null;
    notifyListeners();
    try {
      if (enabled && value > grace && !await _authenticate(reason)) {
        return false;
      }
      await writeGrace(value.inSeconds);
      grace = value;
      return true;
    } catch (_) {
      problem = ForkLockProblem.unavailable;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> _authenticate(String reason) async {
    if (!await platform.available()) {
      problem = ForkLockProblem.deviceNotSecured;
      return false;
    }
    return platform.authenticate(reason);
  }

  Future<bool> unlock(String reason) async {
    if (!ready || !enabled || busy) return false;
    busy = true;
    problem = null;
    notifyListeners();
    try {
      if (!await _authenticate(reason)) return false;
      locked = false;
      // The system prompt itself may have sent the app to the background.
      _hiddenAt = null;
      return true;
    } catch (_) {
      problem = ForkLockProblem.unavailable;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> setEnabled(bool value, String reason) async {
    if (!ready || busy || value == enabled) return false;
    busy = true;
    problem = null;
    notifyListeners();
    var protectionAdded = false;
    try {
      if (!await _authenticate(reason)) return false;
      if (value) {
        await platform.protect(true);
        protectionAdded = true;
      }
      await write(value);
      enabled = value;
      locked = false;
      if (!value) await platform.protect(false);
      return true;
    } catch (_) {
      problem = ForkLockProblem.unavailable;
      if (protectionAdded && !enabled) {
        try {
          await platform.protect(false);
        } catch (_) {
          /* retain protection */
        }
      }
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    try {
      await platform.openSettings();
    } catch (_) {
      problem = ForkLockProblem.unavailable;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(platform.protect(false).catchError((Object _) {}));
    super.dispose();
  }
}
