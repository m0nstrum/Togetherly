/// Системные настройки уведомлений приложения (UX_AUDIT N2).
///
/// Пакет берём у платформы, а не из строки: у форка свой `applicationId`, и
/// зашитый `com.togetherly.love` открывал бы настройки чужого приложения.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Интенты Android по порядку предпочтения: сначала экран уведомлений
/// приложения, затем его общая страница.
List<Uri> androidNotificationSettingsIntents(String package) => [
  for (final action in const [
    'android.settings.APP_NOTIFICATION_SETTINGS',
    'android.settings.APPLICATION_DETAILS_SETTINGS',
  ])
    Uri.parse(
      'intent:#Intent;'
      'action=$action;'
      'S.android.provider.extra.APP_PACKAGE=$package;'
      'end',
    ),
];

/// Открывает настройки уведомлений. false — система не открыла ни один экран:
/// вызывающий код говорит человеку, куда зайти руками.
Future<bool> openSystemNotificationSettings({
  Future<String> Function()? packageName,
}) async {
  if (Platform.isAndroid) {
    // Нативный канал (ForkSettingsChannel.kt): url_launcher intent:-ссылки
    // не открывает.
    try {
      final ok = await _channel.invokeMethod<bool>('openNotificationSettings');
      if (ok == true) return true;
    } catch (e) {
      debugPrint('openSystemNotificationSettings: канал: $e');
    }
    final String package;
    try {
      package = await (packageName ?? _packageName)();
    } catch (e) {
      debugPrint('openSystemNotificationSettings: нет имени пакета: $e');
      return false;
    }
    for (final uri in androidNotificationSettingsIntents(package)) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('openSystemNotificationSettings: $uri: $e');
      }
    }
    return false;
  }
  final ios = Uri.parse('app-settings:');
  try {
    return await canLaunchUrl(ios) && await launchUrl(ios);
  } catch (e) {
    debugPrint('openSystemNotificationSettings: $e');
    return false;
  }
}

Future<String> _packageName() async => (await PackageInfo.fromPlatform()).packageName;

const MethodChannel _channel = MethodChannel('tethered/settings');

/// Страница приложения в системных настройках — там меняют геолокацию после
/// «Не разрешать» (UX_AUDIT G4). false — экран не открылся.
Future<bool> openSystemAppSettings() => _open('openAppSettings', Geolocator.openAppSettings);

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
