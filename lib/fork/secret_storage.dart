/// Independent Android files, cipher configuration and Keystore aliases.
/// The legacy store is read only for migration and never resets on failure.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class ForkSecretStorage {
  static const _ios = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );
  static const auth = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'TetheredAuth',
      resetOnError: false,
    ),
    iOptions: _ios,
  );
  static const cache = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'TetheredCache',
      resetOnError: false,
    ),
    iOptions: _ios,
  );
  static const e2e = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'TetheredE2E',
      resetOnError: false,
    ),
    iOptions: _ios,
  );
  static const legacy = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: _ios,
  );

  /// Copy before deleting only this entry from the shared legacy file.
  /// Failure preserves the original; it must never generate replacement keys.
  static Future<String?> read(FlutterSecureStorage storage, String key) async {
    final current = await storage.read(key: key);
    if (current != null) return current;
    final previous = await legacy.read(key: key);
    if (previous == null) return null;
    await storage.write(key: key, value: previous);
    await legacy.delete(key: key);
    return previous;
  }

  /// Clear the fallback first so a failed deletion cannot revive old secrets.
  static Future<void> delete(FlutterSecureStorage storage, String key) async {
    await legacy.delete(key: key);
    await storage.delete(key: key);
  }
}
