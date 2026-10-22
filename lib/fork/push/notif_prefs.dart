/// Тумблеры уведомлений — действуют сразу (UX_AUDIT G11).
///
/// Источник истины тумблера — SharedPreferences телефона: экран профиля
/// пишет туда первым, а на сервер уходит следом. `PbPushService` же читал
/// запись `users` из authStore, которая обновляется только после `authRefresh`,
/// — выключенный тумблер продолжал показывать уведомления до следующего входа.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ForkNotifPrefs {
  static SharedPreferences? _prefs;

  /// Подтянуть значения с диска. Нужен второму изоляту (фоновый сервис, пуш
  /// FCM): у него свой кэш настроек, и без `reload` он видит старое.
  static Future<void> refresh() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.reload();
    } catch (e) {
      debugPrint('ForkNotifPrefs: $e');
    }
  }

  /// Значение тумблера на телефоне; null — человек его не трогал.
  static bool? local(String key) => _prefs?.getBool(key);

  /// Показывать ли уведомление: выбор на телефоне важнее записи профиля,
  /// запись — важнее умолчания (включено).
  static bool enabled(String key, Object? profileValue) =>
      local(key) ?? (profileValue is bool ? profileValue : true);

  @visibleForTesting
  static void debugUse(SharedPreferences? prefs) => _prefs = prefs;
}
