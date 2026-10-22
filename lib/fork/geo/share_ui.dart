/// Плашки и сообщения о передаче геопозиции (UX_AUDIT G3, G4, G5, G13, G14).
library;

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
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
        content: Text(issue.text ??
            ruEn('Не удалось включить показ', 'Couldn’t turn sharing on')),
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
        content: Text(ruEn(
          'Показ включён, но пока приложение закрыто, партнёр вас не увидит. '
              'Выберите «Всегда» в настройках геопозиции.',
          'Sharing is on, but while the app is closed your partner won’t see '
              'you. Choose “Always” in location settings.',
        )),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: ruEn('Открыть настройки', 'Open settings'),
          onPressed: () => openSettingsFor(context, ShareIssue.denied),
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
/// показа, и это легко принять за обоюдность (G5).
class PartnerBlindBar extends StatelessWidget {
  const PartnerBlindBar({super.key, required this.partnerName, required this.onEnable});

  final String partnerName;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final who = partnerName.trim().isEmpty
        ? ruEn('Партнёр', 'Your partner')
        : partnerName.trim();
    return ForkStatusBar(
      text: ruEn(
        '$who не видит вас: показ вашей геопозиции выключен',
        '$who can’t see you: your location sharing is off',
      ),
      tone: ForkStatusTone.warning,
      actionLabel: ruEn('Включить', 'Turn on'),
      onAction: onEnable,
    );
  }
}
