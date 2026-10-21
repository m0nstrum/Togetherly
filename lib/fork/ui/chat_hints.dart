/// Мелочи чата без отдельного экрана (docs/fork/UX_AUDIT.md, раздел C):
/// статус «в очереди / не отправлено» у текста и голосовых, пузырь для
/// нечитаемого сообщения и однократные подсказки.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/chat_msg.dart';
import '../../services/offline/outbox_service.dart';
import '../e2e/record_codec.dart' show e2eLockedText;

/// Где сообщение сейчас с точки зрения отправки.
enum ForkSendState { sent, queued, failed }

/// Состояние отправки своего сообщения. Чужое всегда [ForkSendState.sent].
ForkSendState forkSendState({
  required bool mine,
  required bool pending,
  required bool poisoned,
}) {
  if (!mine) return ForkSendState.sent;
  if (poisoned) return ForkSendState.failed;
  return pending ? ForkSendState.queued : ForkSendState.sent;
}

/// Сообщение ещё не открылось: ключа нет, в колонке заглушка.
bool forkIsLocked(ChatMsg msg) => !msg.deleted && msg.text == e2eLockedText;

/// Править можно только текст: у голосового, кружка и звонка текста нет, и
/// «Изменить» открывало пустое поле с молчаливой галочкой.
bool forkCanEdit(ChatMsg msg) =>
    !msg.deleted &&
    !msg.isVoice &&
    !msg.isNote &&
    !msg.isCall &&
    !forkIsLocked(msg);

/// Что можно скопировать: непустой читаемый текст.
bool forkCanCopy(ChatMsg msg) =>
    !msg.deleted && !forkIsLocked(msg) && msg.text.trim().isNotEmpty;

/// Вместо галочки у своего сообщения: часы, пока оно в очереди, и «Не
/// отправлено · повторить», если очередь сдалась. Отправленное — [sent].
class ForkSendMark extends StatelessWidget {
  const ForkSendMark({
    super.key,
    required this.messageId,
    required this.mine,
    required this.color,
    required this.sent,
  });

  final String messageId;
  final bool mine;
  final Color color;

  /// Обычная галочка «доставлено / прочитано».
  final Widget sent;

  @override
  Widget build(BuildContext context) {
    if (!mine) return sent;
    final box = OutboxService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([box.pendingCount, box.poisonCount]),
      builder: (context, _) {
        final state = forkSendState(
          mine: mine,
          pending: box.isPending('chat_messages', messageId),
          poisoned: box.isPoisoned('chat_messages', messageId),
        );
        switch (state) {
          case ForkSendState.sent:
            return sent;
          case ForkSendState.queued:
            return Semantics(
              label: ruEn('В очереди на отправку', 'Waiting to send'),
              child: Icon(Icons.schedule_rounded, size: 13, color: color),
            );
          case ForkSendState.failed:
            final red = Theme.of(context).colorScheme.error;
            return Semantics(
              button: true,
              label: ruEn(
                'Не отправлено. Нажмите, чтобы повторить',
                'Not sent. Tap to retry',
              ),
              child: InkWell(
                onTap: () => box.retryPoisonFor('chat_messages', messageId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 14, color: red),
                      const SizedBox(width: 3),
                      Text(
                        ruEn('Не отправлено · повторить', 'Not sent · retry'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        }
      },
    );
  }
}

/// Пузырёк вместо крупного 🔒: понятно, что случилось и что делать.
class ForkLockedText extends StatelessWidget {
  const ForkLockedText({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.lock_outline_rounded, size: 16, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          ruEn('Зашифровано — ждём ключ', 'Encrypted — waiting for the key'),
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ],
  );
}

/// Подсказки, которые показываем один раз на установку.
abstract final class ForkHints {
  static const micTap = 'fork_hint_mic_tap';
  static const gestures = 'fork_hint_chat_gestures';

  static String get micTapText => ruEn(
    'Удерживайте кнопку, чтобы записать. Короткое нажатие переключает '
        'голос и кружок.',
    'Hold the button to record. A quick tap switches between voice and '
        'video note.',
  );

  static String get gesturesText => ruEn(
    'Смахните сообщение — ответ, двойное касание — реакция, долгое — меню. '
        'Долгое нажатие на ✈ — отправить позже.',
    'Swipe a message to reply, double-tap to react, long-press for more. '
        'Long-press ✈ to send later.',
  );

  /// true — подсказку ещё не видели, и метка о показе уже поставлена.
  /// Не смогли прочитать настройки — не показываем: лучше тишина, чем
  /// подсказка при каждом открытии.
  static Future<bool> take(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return false;
      await prefs.setBool(key, true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
