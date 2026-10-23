/// Android screenshot/recents protection. Sensitive content is not built until
/// the platform has acknowledged FLAG_SECURE. Leases support overlapping routes.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dict_strings.dart' show ruEn;

class ForkScreenLease {
  ForkScreenLease._();
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (--ForkScreenSecurity._leases == 0) {
      try {
        await ForkScreenSecurity._set(false);
      } catch (_) {
        /* retain protection on failure */
      }
    }
  }
}

abstract final class ForkScreenSecurity {
  static const _channel = MethodChannel('tethered/screen_security');
  static int _leases = 0;
  static Future<void>? _tail;

  static Future<void> _set(bool secure) {
    final command = (_tail ?? Future<void>.value()).then((_) async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<void>('setSecure', secure);
      }
    });
    final completed = command.then((_) {}, onError: (Object _) {});
    _tail = completed;
    unawaited(
      completed.then((_) {
        if (identical(_tail, completed)) _tail = null;
      }),
    );
    return command;
  }

  static Future<ForkScreenLease> acquire() async {
    _leases++;
    try {
      await _set(true);
      return ForkScreenLease._();
    } catch (_) {
      if (--_leases == 0) {
        unawaited(_set(false).catchError((Object _) {}));
      }
      rethrow;
    }
  }
}

class ForkSecureScreen extends StatefulWidget {
  const ForkSecureScreen({required this.builder, super.key});
  final WidgetBuilder builder;
  @override
  State<ForkSecureScreen> createState() => _ForkSecureScreenState();
}

class _ForkSecureScreenState extends State<ForkSecureScreen> {
  ForkScreenLease? _lease;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_protect());
  }

  Future<void> _protect() async {
    setState(() => _failed = false);
    try {
      final lease = await ForkScreenSecurity.acquire();
      if (!mounted) {
        await lease.release();
        return;
      }
      setState(() => _lease = lease);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_lease?.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lease != null) return widget.builder(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ruEn(
                      'Не удалось защитить экран',
                      'Could not protect this screen',
                    ),
                  ),
                  TextButton(
                    onPressed: _protect,
                    child: Text(ruEn('Повторить', 'Try again')),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
