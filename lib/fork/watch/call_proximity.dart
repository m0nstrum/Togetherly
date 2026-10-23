import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android turns the display off near the face only while using the earpiece.
abstract final class ForkCallProximity {
  static const _channel = MethodChannel('tethered/call_audio');
  static Future<void> active(bool active) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setCallActive', active);
    } catch (e) {
      // Audio still works on devices without a proximity sensor.
      debugPrint('Call proximity unavailable: ${e.runtimeType}');
    }
  }
}
