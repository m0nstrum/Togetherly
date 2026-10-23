/// Системные настройки уведомлений приложения (UX_AUDIT N2).
///
/// Пакет берём у платформы, а не из строки: у форка свой `applicationId`, и
/// зашитый `com.togetherly.love` открывал бы настройки чужого приложения.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:geolocator/geolocator.dart';

/// Открывает настройки уведомлений своего пакета через Android-канал.
/// Если экран недоступен, плагин открывает общие настройки приложения.
Future<bool> openSystemNotificationSettings({
  Future<bool> Function()? fallback,
}) => _open('openNotificationSettings', fallback ?? Geolocator.openAppSettings);

const MethodChannel _channel = MethodChannel('tethered/settings');

/// Страница приложения в системных настройках — там меняют геолокацию после
/// «Не разрешать» (UX_AUDIT G4). false — экран не открылся.
Future<bool> openSystemAppSettings() =>
    _open('openAppSettings', Geolocator.openAppSettings);

/// Системный переключатель геолокации телефона (когда она выключена целиком).
Future<bool> openSystemLocationSettings() =>
    _open('openLocationSettings', Geolocator.openLocationSettings);

Future<bool> _open(String method, Future<bool> Function() fallback) async {
  if (Platform.isAndroid) {
    try {
      if (await _channel.invokeMethod<bool>(method) == true) return true;
    } catch (e) {
      debugPrint('system_settings.$method: канал: $e');
    }
  }
  try {
    return await fallback();
  } catch (e) {
    debugPrint('system_settings.$method: $e');
    return false;
  }
}
