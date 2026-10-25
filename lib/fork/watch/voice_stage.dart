/// Стадии голосового звонка и причины сбоя — то, что человек видит вместо
/// одного «Звоним…» на всё (UX_AUDIT L2–L7, L12).
library;

import '../../dict_strings.dart' show ruEn;

enum VoiceStage {
  /// Звонка нет.
  idle,

  /// Зовём партнёра, он ещё не откликнулся.
  calling,

  /// Партнёр откликнулся — ищем путь между телефонами (напрямую или через
  /// свой сервер-ретранслятор).
  connecting,

  /// Говорим.
  live,

  /// Связь пропала посреди разговора — восстанавливаем.
  reconnecting,

  /// Не вышло — см. [VoiceProblem].
  failed,
}

enum VoiceProblem {
  /// Нет доступа к микрофону.
  noMic,

  /// Нет ключа пары: сигналы звонка ходят только шифром.
  noKey,

  /// Нет связи с сервером: зов не ушёл.
  network,

  /// Комната не подключилась — звонить некуда.
  noChannel,

  /// Партнёр не ответил.
  noAnswer,

  /// Партнёр отклонил.
  declined,

  /// Телефоны не нашли путь друг к другу (обычно — мобильный интернет без
  /// ретранслятора на сервере).
  noRoute,
}

/// Текст для плашки звонка. [name] — как зовут партнёра.
String voiceStageText(
  VoiceStage stage,
  VoiceProblem? problem, {
  String name = '',
  Duration? talked,
}) {
  final who = name.isEmpty ? ruEn('партнёр', 'your partner') : name;
  final whoCap = name.isEmpty ? ruEn('Партнёр', 'Your partner') : name;
  String clock(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  return switch (stage) {
    VoiceStage.idle => '',
    VoiceStage.calling => ruEn(
      'Зовём $who… ждём ответа',
      'Calling $who… waiting for an answer',
    ),
    VoiceStage.connecting => ruEn(
      '$whoCap ответил(а) — соединяем телефоны…',
      '$whoCap answered — connecting the phones…',
    ),
    VoiceStage.live =>
      talked == null
          ? ruEn('На связи', 'Connected')
          : ruEn('На связи · ${clock(talked)}', 'Connected · ${clock(talked)}'),
    VoiceStage.reconnecting => ruEn(
      'Связь прервалась — восстанавливаем…',
      'Connection dropped — reconnecting…',
    ),
    VoiceStage.failed => switch (problem) {
      VoiceProblem.noMic => ruEn(
        'Нет доступа к микрофону — разрешите его в настройках телефона',
        'No microphone access — allow it in your phone settings',
      ),
      VoiceProblem.noKey => ruEn(
        'Ключи шифрования ещё не готовы — звонок без них не идёт',
        'Encryption keys aren’t ready — calls need them',
      ),
      VoiceProblem.network => ruEn(
        'Нет связи с сервером — зов не ушёл',
        'Can’t reach the server — the call didn’t go out',
      ),
      VoiceProblem.noChannel => ruEn(
        'Комната ещё не подключилась — попробуйте через пару секунд',
        'The room isn’t connected yet — try again in a moment',
      ),
      VoiceProblem.noAnswer => ruEn(
        '$whoCap не ответил(а) — возможно, не в комнате',
        '$whoCap didn’t answer — maybe not in the room',
      ),
      VoiceProblem.declined => ruEn(
        '$whoCap сейчас не может говорить',
        '$whoCap can’t talk right now',
      ),
      VoiceProblem.noRoute => ruEn(
        'Телефоны не смогли соединиться. Если оба на мобильном интернете — '
            'на сервере нужен ретранслятор (TURN)',
        'The phones couldn’t connect. If both are on mobile data, '
            'the server needs a relay (TURN)',
      ),
      null => ruEn('Звонок не удался', 'The call failed'),
    },
  };
}
