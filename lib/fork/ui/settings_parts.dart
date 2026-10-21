/// Куски экрана настроек форка (docs/fork/UX_AUDIT.md: N1, N14).
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn, trKey;
import '../../services/coin_store.dart' show kCoinsPurchasable;
import '../../widgets/settings_scaffold.dart';
import '../e2e/backup_ui.dart';
import '../e2e/fork_e2e.dart';

/// Секция «Шифрование»: бэкап ключей. Без сервиса шифрования строки нет, и
/// заголовок без строк тоже не рисуем.
class ForkEncryptionSection extends StatelessWidget {
  const ForkEncryptionSection({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ForkE2E.service,
    builder: (context, svc, _) => svc == null
        ? const SizedBox.shrink()
        : SettingsCollapsible(
            prefsKey: 'encryption',
            title: ruEn('Шифрование', 'Encryption'),
            icon: Icons.lock_rounded,
            children: const [ForkE2EBackupRow()],
          ),
  );
}

/// Подпись строки монет в настройках — та же, что в профиле: где паков нет,
/// это не магазин, а «Задания за монеты» (N14).
String forkCoinsRowTitle() =>
    trKey(!Platform.isIOS && kCoinsPurchasable ? 'coinShopTitle' : 'coinEarnTitle');
