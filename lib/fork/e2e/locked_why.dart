/// Почему запись пары не открылась и что с этим делать (UX_AUDIT A9).
///
/// Раньше вместо сообщения стояло «Зашифровано — ждём ключ», а очередь с
/// записью без ключа предлагала «повторить», что ничего не меняло. Здесь
/// одна причина на все места: пузырь в чате, плашка очереди и лист с
/// объяснением и действием, которое правда помогает.
library;

import 'themed_route.dart';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import 'backup_ui.dart' show ForkE2ERestoreScreen;
import 'e2e_service.dart';
import 'fork_e2e.dart';

enum ForkLockedWhy {
  /// Шифрование ещё поднимается (первые секунды после запуска).
  starting,

  /// Шифрование на этом телефоне не запустилось.
  notStarted,

  /// Новый телефон: ключи лежат в бэкапе, нужна фраза или пароль.
  needsRestore,

  /// У партнёра ещё нет ключей: старая версия или давно не открывал.
  waitingPartner,

  /// Ключ пары не дошёл: партнёру надо открыть приложение.
  waitingKey,

  /// Ключи сервера не сходятся — ключ пары не выдаётся.
  tampered,

  /// Ключ пары есть, но запись закрыта старым ключом, которого тут нет.
  oldKey,
}

/// Причина по состоянию шифрования: [started] — сервис поднялся,
/// [failed] — не поднялся и не поднимается, [restore] — есть бэкап и нет
/// своих ключей, [status] — состояние пары, [hasKey] — есть ли текущий
/// ключ пары.
ForkLockedWhy forkLockedWhy({
  required bool started,
  bool failed = false,
  required bool restore,
  PairE2EStatus? status,
  required bool hasKey,
}) {
  if (!started) {
    return failed ? ForkLockedWhy.notStarted : ForkLockedWhy.starting;
  }
  if (restore || status == PairE2EStatus.needsRestore) {
    return ForkLockedWhy.needsRestore;
  }
  if (status == PairE2EStatus.tampered) return ForkLockedWhy.tampered;
  if (!hasKey) {
    return status == PairE2EStatus.waitingPartner
        ? ForkLockedWhy.waitingPartner
        : ForkLockedWhy.waitingKey;
  }
  return ForkLockedWhy.oldKey;
}

/// Причина для пары [groupId] сейчас.
ForkLockedWhy forkLockedWhyNow(String groupId) {
  final s = ForkE2E.service.value;
  return forkLockedWhy(
    started: s != null,
    failed: ForkE2E.startFailed.value,
    restore: s?.needsRestore.value ?? false,
    status: s?.status.value[groupId],
    hasKey: s?.currentKey(groupId) != null,
  );
}

/// Можно ли писать в пару: без ключа запись в очереди не уйдёт.
bool forkSealBlocked(String groupId) {
  if (groupId.isEmpty) return false;
  final why = forkLockedWhyNow(groupId);
  return why != ForkLockedWhy.oldKey && why != ForkLockedWhy.starting;
}

/// Короткая подпись — в пузырь и плашку.
String forkLockedShort(ForkLockedWhy why) => switch (why) {
      ForkLockedWhy.starting =>
        ruEn('Открываем шифрование…', 'Opening encryption…'),
      ForkLockedWhy.notStarted =>
        ruEn('Шифрование не запустилось', 'Encryption did not start'),
      ForkLockedWhy.needsRestore =>
        ruEn('Нужно восстановить ключи', 'Restore your keys'),
      ForkLockedWhy.waitingPartner =>
        ruEn('У партнёра ещё нет ключей', 'Partner has no keys yet'),
      ForkLockedWhy.waitingKey =>
        ruEn('Ждём ключ от партнёра', 'Waiting for partner’s key'),
      ForkLockedWhy.tampered =>
        ruEn('Ключи не сходятся', 'Keys do not match'),
      ForkLockedWhy.oldKey =>
        ruEn('Закрыто старым ключом', 'Locked with an old key'),
    };

/// Объяснение — в лист.
String forkLockedLong(ForkLockedWhy why) => switch (why) {
      ForkLockedWhy.starting => ruEn(
          'Приложение только запустилось и поднимает ключи. Обычно это пара '
              'секунд — сообщение откроется само.',
          'The app has just started and is loading keys. It usually takes a '
              'couple of seconds — the message will open on its own.'),
      ForkLockedWhy.notStarted => ruEn(
          'На этом телефоне не поднялось шифрование, поэтому записи пары не '
              'открываются и не отправляются. Чаще всего помогает повтор; если нет '
              '— перезапустите приложение.',
          'Encryption did not start on this phone, so pair records can’t be '
              'opened or sent. Retrying usually helps; if not, restart the app.'),
      ForkLockedWhy.needsRestore => ruEn(
          'Это новый телефон или переустановка: ключи лежат в зашифрованном '
              'бэкапе. Введите фразу или пароль — история откроется.',
          'This is a new phone or a reinstall: your keys are in the encrypted '
              'backup. Enter your phrase or password to open your history.'),
      ForkLockedWhy.waitingPartner => ruEn(
          'У партнёра ещё нет ключей шифрования — обычно у него старая версия '
              'или он давно не открывал приложение. Как только откроет, ключ '
              'придёт сам.',
          'Your partner has no encryption keys yet — usually an old version or '
              'the app hasn’t been opened in a while. The key arrives once they '
              'open it.'),
      ForkLockedWhy.waitingKey => ruEn(
          'Ключ пары выдаёт телефон партнёра. Попросите партнёра открыть '
              'приложение — ключ придёт сам, ничего нажимать не нужно.',
          'Your partner’s phone hands out the pair key. Ask your partner to '
              'open the app — the key arrives on its own.'),
      ForkLockedWhy.tampered => ruEn(
          'Ключи на сервере не сходятся с теми, что вы сверяли. Пока это так, '
              'ключ пары не выдаётся. Сверьте эмодзи с партнёром заново в '
              'настройках шифрования.',
          'The keys on the server don’t match the ones you verified. Until this '
              'is fixed, the pair key is not handed out. Re-verify emoji with '
              'your partner in encryption settings.'),
      ForkLockedWhy.oldKey => ruEn(
          'Сообщение закрыто ключом, которого на этом телефоне нет: обычно оно '
              'пришло до переустановки или смены ключей. Если ключи были в '
              'бэкапе, восстановите их; иначе его не открыть — так и задумано: '
              'сервер прочитать его не может.',
          'This message is locked with a key this phone doesn’t have — usually '
              'it came before a reinstall or a key change. If your keys were '
              'backed up, restore them; otherwise it can’t be opened — by '
              'design, the server can’t read it either.'),
    };

/// Лист «почему не открылось» с действием, которое правда помогает.
/// [navigator] — когда [context] выше навигатора (плашка поверх приложения).
Future<void> showForkLockedSheet(
  BuildContext context,
  String groupId, {
  NavigatorState? navigator,
}) async {
  final why = forkLockedWhyNow(groupId);
  final nav = navigator ?? Navigator.of(context);
  final restore = ForkE2E.service.value?.needsRestore.value ?? false;
  await showModalBottomSheet<void>(
    context: nav.context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    forkLockedShort(why),
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(forkLockedLong(why)),
            const SizedBox(height: 16),
            if (why == ForkLockedWhy.notStarted)
              FilledButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: Text(ruEn('Повторить', 'Retry')),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final ok = await ForkE2E.retry();
                  final destinationContext = nav.context;
                  if (!destinationContext.mounted) return;
                  final m = ScaffoldMessenger.maybeOf(destinationContext);
                  m?.showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(ok
                        ? ruEn('Шифрование запустилось', 'Encryption started')
                        : ruEn('Снова не вышло — перезапустите приложение',
                            'Failed again — restart the app')),
                  ));
                },
              )
            else if (why == ForkLockedWhy.needsRestore ||
                (why == ForkLockedWhy.oldKey && restore))
              FilledButton.icon(
                icon: const Icon(Icons.restore_rounded),
                label: Text(ruEn('Восстановить ключи', 'Restore keys')),
                onPressed: () {
                  Navigator.pop(ctx);
                  nav.push(forkE2ERoute<void>(context, const ForkE2ERestoreScreen()));
                },
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ruEn('Понятно', 'Got it')),
              ),
          ],
        ),
      ),
    ),
  );
}
