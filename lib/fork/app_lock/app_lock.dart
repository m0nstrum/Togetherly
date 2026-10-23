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
  });
  static const prefKey = 'fork.app_lock.enabled';
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
  );

  final ForkLockPlatform platform;
  final Future<bool> Function() read;
  final Future<void> Function(bool) write;
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
      locked = true;
      notifyListeners();
    }
  }

  void resumed() {
    covered = false;
    notifyListeners();
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
