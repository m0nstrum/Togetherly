import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_storage.dart';

/// Сессия PocketBase в Keystore/Keychain, а не в SharedPreferences
/// (docs/history/PLAN.md, S6; AUDIT §1: токен лежал открытым текстом).
///
/// Токен, сохранённый прежней версией в SharedPreferences, переносится при
/// первом запуске и оттуда стирается.
abstract final class ForkSecureAuthStore {
  static const _storage = ForkSecretStorage.auth;

  /// Хранилище для [PocketBase]. [prefsKey] — ключ, под которым токен лежал в
  /// SharedPreferences у апстрима; под ним же он живёт и в Keystore.
  static Future<AsyncAuthStore> open(
    String prefsKey, {
    @visibleForTesting FlutterSecureStorage storage = _storage,
  }) async {
    final initial = await _migrate(prefsKey, storage);
    return AsyncAuthStore(
      initial: initial,
      save: (data) => storage.write(key: prefsKey, value: data),
      clear: () => ForkSecretStorage.delete(storage, prefsKey),
    );
  }

  static Future<String?> _migrate(
    String key,
    FlutterSecureStorage storage,
  ) async {
    String? secure;
    try {
      secure = await ForkSecretStorage.read(storage, key);
    } catch (e) {
      debugPrint('ForkSecureAuthStore: Keystore не прочитан — $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(key);
    if (legacy == null) return secure;
    if (secure == null || secure.isEmpty) {
      try {
        await storage.write(key: key, value: legacy);
        secure = legacy;
      } catch (e) {
        // Не перенёсся — не стираем, иначе человек потеряет вход.
        debugPrint('ForkSecureAuthStore: перенос не удался — $e');
        return legacy;
      }
    }
    await prefs.remove(key);
    return secure;
  }
}
