/// Плашки и сообщения о передаче геопозиции (UX_AUDIT G3, G4, G5, G13, G14).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/live_location_service.dart';
import '../system_settings.dart';
import '../ui/feedback.dart';
import 'geo_status.dart';

/// Открывает системный экран, где [issue] лечится. Не открылся — говорит,
/// куда зайти руками.
Future<void> openSettingsFor(BuildContext context, ShareIssue issue) async {
  final opened = issue.needsLocationSettings
      ? await openSystemLocationSettings()
      : await openSystemAppSettings();
  if (!opened && context.mounted) {
    ForkNotice.info(
      context,
      ruEn(
        'Откройте настройки телефона → Приложения → Togetherly → Разрешения',
        'Open phone settings → Apps → Togetherly → Permissions',
      ),
    );
  }
}

/// Сообщение после неудачной попытки включить показ: причина и, если она
/// лечится в системе, кнопка «Открыть настройки».
void showShareDenied(BuildContext context, ShareIssue issue) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final cs = Theme.of(context).colorScheme;
  final label = issue.actionLabel;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          issue.text ??
              ruEn('Не удалось включить показ', 'Couldn’t turn sharing on'),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.errorContainer,
        duration: const Duration(seconds: 8),
        action: label == null
            ? null
            : SnackBarAction(
                label: label,
                onPressed: () => openSettingsFor(context, issue),
              ),
      ),
    );
}

/// iPhone: выдали только «При использовании» — закрытое приложение
/// партнёр не увидит.
void showBackgroundLimited(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          ruEn(
            'Показ включён, но в фоне телефон может его остановить. Чтобы партнёр '
                'видел вас и при закрытом приложении, выберите «Разрешать всегда».',
            'Sharing is on, but the phone may stop it in the background. To stay '
                'visible while the app is closed, choose “Allow all the time”.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: ruEn('Разрешить', 'Allow'),
          // fork: прямо на страницу разрешения, где есть «Разрешать всегда».
          onPressed: () =>
              unawaited(LiveLocationService.instance.requestAlways()),
        ),
      ),
    );
}

/// Плашка «почему не передаётся». Пустая, если причины нет.
class ShareIssueBar extends StatelessWidget {
  const ShareIssueBar({super.key, required this.issue});

  final ShareIssue issue;

  @override
  Widget build(BuildContext context) {
    final text = issue.text;
    if (text == null) return const SizedBox.shrink();
    final label = issue.actionLabel;
    return ForkStatusBar(
      text: text,
      tone: ForkStatusTone.warning,
      actionLabel: label,
      onAction: label == null ? null : () => openSettingsFor(context, issue),
    );
  }
}

/// «Партнёр вас не видит»: свою точку на большой карте человек видит и без
/// показа, и это легко принять за обоюдность (G5). fork (D11): показ
/// взаимный — без своего не видно и партнёра, об этом и говорим.
class PartnerBlindBar extends StatelessWidget {
  const PartnerBlindBar({
    super.key,
    required this.partnerName,
    required this.onEnable,
  });

  final String partnerName;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final who = partnerName.trim().isEmpty
        ? ruEn('партнёр', 'your partner')
        : partnerName.trim();
    return ForkStatusBar(
      text: ruEn(
        'Включите свою геопозицию, чтобы видеть, где $who. Геопозицией '
            'делятся только взаимно: пока ваша выключена, вы не видите '
            'друг друга.',
        'Turn on your location to see where $who is. Sharing is mutual: '
            'while yours is off, you can’t see each other.',
      ),
      tone: ForkStatusTone.warning,
      actionLabel: ruEn('Включить', 'Turn on'),
      onAction: onEnable,
    );
  }
}
