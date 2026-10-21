/// Дойдут ли уведомления: разрешение системы и путь доставки
/// (UX_AUDIT G9).
///
/// Раньше выключенные в системе уведомления и «живой» путь доставки были
/// невидимы: тумблеры в приложении включены, а сообщения не приходят. Здесь —
/// вердикт одной структурой и плашка, которую можно поставить в настройки
/// уведомлений.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/background_reliability_service.dart';
import '../../services/fcm_service.dart';
import '../system_settings.dart';
import '../ui/feedback.dart';

/// Каким путём уведомления доходят, пока приложение закрыто.
enum PushRoute {
  /// Пуш Google будит приложение сам.
  fcm,

  /// Фоновое соединение (foreground-сервис, строка «на связи» в шторке).
  socket,

  /// iPhone: доставка идёт через APNs, выбирать нечего.
  apns,
}

class PushHealth {
  const PushHealth({
    required this.systemEnabled,
    required this.route,
    this.batteryRestricted = false,
  });

  /// Разрешены ли уведомления в системе. null — узнать не удалось.
  final bool? systemEnabled;
  final PushRoute route;

  /// Фоновое соединение без исключения из оптимизации батареи: Android
  /// усыпляет его, и сообщения приходят только при открытии приложения.
  final bool batteryRestricted;

  bool get blocked => systemEnabled == false;

  /// Тревожная строка; null — всё в порядке.
  String? get problem {
    if (blocked) {
      return ruEn(
        'Уведомления выключены в настройках телефона — сообщения не придут',
        'Notifications are turned off in phone settings — messages won’t arrive',
      );
    }
    if (route == PushRoute.socket && batteryRestricted) {
      return ruEn(
        'Фоновая связь может засыпать: Android ограничивает приложение по батарее',
        'Background connection may sleep: Android limits the app’s battery use',
      );
    }
    return null;
  }

  /// Спокойная строка о пути доставки.
  String get routeText => switch (route) {
        PushRoute.fcm => ruEn(
            'Доставка: пуши Google — приложению не нужно быть открытым',
            'Delivery: Google push — the app doesn’t need to be open'),
        PushRoute.socket => ruEn(
            'Доставка: фоновое соединение (строка «на связи» в шторке)',
            'Delivery: background connection (the “connected” line in the shade)'),
        PushRoute.apns => ruEn(
            'Доставка: системные пуши Apple',
            'Delivery: Apple push notifications'),
      };

  static Future<PushHealth> check() async {
    bool? enabled;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      if (Platform.isAndroid) {
        enabled = await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
      } else if (Platform.isIOS) {
        final p = await plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
        enabled = p?.isEnabled;
      }
    } catch (e) {
      debugPrint('PushHealth: разрешение не прочиталось: $e');
    }
    if (!Platform.isAndroid) {
      return PushHealth(systemEnabled: enabled, route: PushRoute.apns);
    }
    await FcmService.instance.settled
        .timeout(const Duration(seconds: 5), onTimeout: () {});
    if (FcmService.instance.ready) {
      return PushHealth(systemEnabled: enabled, route: PushRoute.fcm);
    }
    final exempt = await BackgroundReliabilityService.instance.isExempt();
    return PushHealth(
      systemEnabled: enabled,
      route: PushRoute.socket,
      batteryRestricted: !exempt,
    );
  }
}

/// Плашка состояния доставки для экрана настроек уведомлений. Сама
/// перечитывает состояние, когда человек вернулся из системных настроек.
class PushHealthTile extends StatefulWidget {
  const PushHealthTile({super.key});

  @override
  State<PushHealthTile> createState() => _PushHealthTileState();
}

class _PushHealthTileState extends State<PushHealthTile> with WidgetsBindingObserver {
  PushHealth? _health;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final h = await PushHealth.check();
    if (mounted) setState(() => _health = h);
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    if (h == null) return const SizedBox.shrink();
    final problem = h.problem;
    if (problem != null) {
      final settings = h.blocked;
      return ForkStatusBar(
        text: problem,
        tone: ForkStatusTone.warning,
        actionLabel: settings ? ruEn('Открыть настройки', 'Open settings') : null,
        onAction: settings
            ? () async {
                final ok = await openSystemNotificationSettings();
                if (!ok && context.mounted) {
                  ForkNotice.info(
                    context,
                    ruEn('Откройте настройки телефона → Уведомления',
                        'Open phone settings → Notifications'),
                  );
                }
              }
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        h.routeText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
