/// Почему снова экран входа (UX_AUDIT A13).
///
/// Раньше человека молча выбрасывало на вход: сессию отозвал сервер (сменили
/// пароль на другом устройстве, вышли везде) или вход просто устарел. Он не
/// понимал, что случилось и не пропала ли переписка. Причина запоминается в
/// момент отзыва ([ForkSessionEnd.revoked]) — до перезапуска, — а экран
/// входа один раз объясняет её словами.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show ruEn;

abstract final class ForkSessionEnd {
  static const _key = 'fork_session_revoked';

  /// Сервер отверг вход (401/403): запомнить до следующего экрана входа.
  static Future<void> revoked() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (e) {
      debugPrint('ForkSessionEnd: $e');
    }
  }

  /// Забрать причину: true — сессию отозвал сервер. Отметка снимается.
  static Future<bool> take() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(_key) ?? false;
      if (v) await p.remove(_key);
      return v;
    } catch (e) {
      debugPrint('ForkSessionEnd: $e');
      return false;
    }
  }

  static String text({required bool revoked}) => revoked
      ? ruEn(
          'Вход на этом телефоне завершился: сервер его отозвал — обычно так бывает, '
              'если сменить пароль или выйти со всех устройств. Войдите снова — '
              'пара, переписка и ключи шифрования остались на телефоне.',
          'You were signed out on this phone: the server revoked the session — '
              'usually after a password change or signing out everywhere. Sign in '
              'again — your pair, chat and encryption keys are still on this phone.',
        )
      : ruEn(
          'Вход устарел — так бывает, если долго не открывать приложение. Войдите '
              'снова — пара, переписка и ключи шифрования остались на телефоне.',
          'Your sign-in expired — this happens after a long break. Sign in again '
              '— your pair, chat and encryption keys are still on this phone.',
        );
}

/// Экран входа для вернувшегося человека: один раз объясняет, почему он тут.
class ForkSessionNote extends StatefulWidget {
  const ForkSessionNote({super.key, required this.child});
  final Widget child;

  /// Объяснили в этом запуске — второй раз не мешаем.
  static bool _shown = false;

  @visibleForTesting
  static void debugReset() => _shown = false;

  @override
  State<ForkSessionNote> createState() => _ForkSessionNoteState();
}

class _ForkSessionNoteState extends State<ForkSessionNote> {
  @override
  void initState() {
    super.initState();
    if (ForkSessionNote._shown) return;
    ForkSessionNote._shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _explain());
  }

  Future<void> _explain() async {
    final revoked = await ForkSessionEnd.take();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_clock_rounded),
        title: Text(ruEn('Нужно войти снова', 'Please sign in again')),
        content: Text(ForkSessionEnd.text(revoked: revoked)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ruEn('Понятно', 'OK')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
