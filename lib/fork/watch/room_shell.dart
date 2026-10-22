/// Комната совместного просмотра как в Rave (просьба владельца 22.10:
/// «сейчас абсолютно не понятно, как оно работает»).
///
/// Сверху шапка: кто в комнате, позвать, звонок. Под ней окно видео (страница
/// комнаты в режиме «только плеер»), полоса «что играет» с кнопками и ниже
/// на всю высоту — переписка, в которой видно и действия: «Аня — пауза на
/// 12:34», «Вы включили: YouTube». Повернул телефон — видео во весь экран, чат
/// поверх кнопкой.
library;

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/watch_voice_service.dart';
import '../e2e/room_chat.dart';
import '../e2e/room_chat_ui.dart';
import 'room_live.dart';
import 'voice_stage.dart';

/// Шапка: назад, кто в комнате, позвать, звонок, ссылка.
class ForkRoomTopBar extends StatelessWidget {
  const ForkRoomTopBar({
    super.key,
    required this.partnerName,
    required this.partnerHere,
    required this.onBack,
    required this.onInvite,
    required this.invited,
    required this.voice,
    required this.onCall,
    required this.onShare,
    required this.onCopy,
  });

  final String partnerName;
  final bool partnerHere;
  final VoidCallback onBack;
  final VoidCallback onInvite;

  /// Только что позвали — кнопка ждёт, пока партнёр придёт.
  final bool invited;
  final WatchVoiceService? voice;
  final VoidCallback onCall;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = partnerName.trim().isEmpty ? ruEn('Партнёр', 'Partner') : partnerName.trim();
    final stage = voice?.stage ?? VoiceStage.idle;
    final inCall = stage != VoiceStage.idle;
    final live = stage == VoiceStage.live;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          IconButton(
            tooltip: ruEn('Выйти из комнаты', 'Leave the room'),
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruEn('Смотрим вместе', 'Watching together'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      key: const ValueKey('fork-room-presence-dot'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: partnerHere || live ? const Color(0xFF30A46C) : cs.outline,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        inCall
                            ? voiceStageText(stage, voice?.problem, name: name)
                            : partnerHere
                            ? ruEn('$name в комнате', '$name is here')
                            : invited
                                ? ruEn('Позвали — ждём $name', 'Invited — waiting for $name')
                                : ruEn('$name не в комнате', '$name isn’t here'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!partnerHere)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: TextButton.icon(
                onPressed: invited ? null : onInvite,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text(ruEn('Позвать', 'Invite')),
              ),
            ),
          IconButton(
            tooltip: inCall ? ruEn('Открыть звонок', 'Open the call') : ruEn('Позвонить', 'Call'),
            onPressed: onCall,
            style: inCall
                ? IconButton.styleFrom(
                    backgroundColor: live ? const Color(0xFF30A46C) : cs.tertiaryContainer,
                    foregroundColor: live ? Colors.white : cs.onTertiaryContainer,
                  )
                : null,
            icon: Icon(inCall ? Icons.phone_in_talk_rounded : Icons.call_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: ruEn('Ещё', 'More'),
            onSelected: (v) => v == 'share' ? onShare() : onCopy(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.ios_share_rounded),
                  title: Text(ruEn('Поделиться ссылкой', 'Share the link')),
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_rounded),
                  title: Text(ruEn('Скопировать ссылку для браузера', 'Copy the browser link')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Полоса «что играет» под окном видео.
class ForkNowPlaying extends StatelessWidget {
  const ForkNowPlaying({
    super.key,
    required this.live,
    required this.onPick,
    required this.onToggle,
    required this.onTogether,
    required this.onPauseBoth,
    required this.onFullscreen,
  });

  final ForkRoomLive live;
  final VoidCallback onPick;
  final VoidCallback onToggle;
  final VoidCallback onTogether;
  final VoidCallback onPauseBoth;
  final VoidCallback onFullscreen;

  IconData get _icon => switch (live.kind) {
        'youtube' => Icons.smart_display_rounded,
        'file' || 'video' => Icons.movie_rounded,
        'yadisk' || 'drive' || 'mega' => Icons.cloud_rounded,
        _ => Icons.play_circle_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!live.hasVideo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ruEn('Что смотрим?', 'What are we watching?'),
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    live.offline
                        ? ruEn('Нет связи — переподключаемся…', 'Offline — reconnecting…')
                        : ruEn('Видео включится у обоих сразу', 'It starts for both of you at once'),
                    style: tt.bodySmall?.copyWith(color: live.offline ? cs.error : cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('fork-room-pick'),
              onPressed: onPick,
              icon: const Icon(Icons.add_rounded),
              label: Text(ruEn('Выбрать видео', 'Choose a video')),
            ),
          ],
        ),
      );
    }
    final head = live.title.isNotEmpty ? live.title : (live.label.isEmpty ? ruEn('Видео', 'Video') : live.label);
    final sub = live.offline
        ? ruEn('Нет связи — переподключаемся…', 'Offline — reconnecting…')
        : live.lastAct.isNotEmpty
            ? live.lastAct
            : live.manual
                ? ruEn('Этот плеер каждый жмёт сам — по отсчёту', 'Each of you presses play — on the countdown')
                : live.status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(head,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty)
                  Text(sub,
                      key: const ValueKey('fork-room-now-sub'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: live.offline ? cs.error : cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (live.manual) ...[
            IconButton(
              tooltip: ruEn('Начать вместе: отсчёт 3·2·1', 'Start together: 3·2·1'),
              icon: const Icon(Icons.timer_3_rounded),
              onPressed: onTogether,
            ),
            IconButton(
              tooltip: ruEn('Пауза у обоих', 'Pause for both'),
              icon: const Icon(Icons.pause_circle_outline_rounded),
              onPressed: onPauseBoth,
            ),
          ] else
            IconButton(
              key: const ValueKey('fork-room-toggle'),
              tooltip: live.playing ? ruEn('Пауза у обоих', 'Pause for both') : ruEn('Играть у обоих', 'Play for both'),
              icon: Icon(live.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: onToggle,
            ),
          IconButton(
            tooltip: ruEn('Во весь экран', 'Full screen'),
            icon: const Icon(Icons.fullscreen_rounded),
            onPressed: onFullscreen,
          ),
          IconButton(
            key: const ValueKey('fork-room-change'),
            tooltip: ruEn('Другое видео', 'Another video'),
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onPick,
          ),
        ],
      ),
    );
  }
}

/// Переписка комнаты вместе с событиями просмотра.
class ForkRoomChatPanel extends StatefulWidget {
  const ForkRoomChatPanel({
    super.key,
    required this.chat,
    required this.live,
    this.starting = false,
  });

  /// null — чата нет (ключи пары не обменялись или шифрование не поднялось).
  final RoomChat? chat;
  final ForkRoomLive live;

  /// Чат ещё поднимается.
  final bool starting;

  @override
  State<ForkRoomChatPanel> createState() => _ForkRoomChatPanelState();
}

class _ForkRoomChatPanelState extends State<ForkRoomChatPanel> {
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chat = widget.chat;
    final text = _input.text.trim();
    if (chat == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await chat.send(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final listen = Listenable.merge([widget.live, ?chat]);
    return ListenableBuilder(
      listenable: listen,
      builder: (context, _) => _body(context, chat),
    );
  }

  Widget _body(BuildContext context, RoomChat? chat) {
    final cs = Theme.of(context).colorScheme;
    final items = <({int at, RoomMessage? m, ForkRoomLine? l})>[
      for (final m in chat?.messages ?? const <RoomMessage>[]) (at: m.at, m: m, l: null),
      for (final l in widget.live.lines) (at: l.at, m: null, l: l),
    ]..sort((a, b) => a.at.compareTo(b.at));
    final usable = chat != null && !chat.noPairKey;
    final warn = chat != null && !chat.secure;
    final ask = chat != null && chat.browser && !chat.openAllowed && !chat.noPairKey;
    final status = chat == null
        ? (widget.starting
            ? ruEn('Поднимаем шифрованный чат…', 'Starting the encrypted chat…')
            : ruEn('Чат появится, когда ключи пары обменяются', 'Chat appears once your pair keys are exchanged'))
        : forkRoomChatStatus(chat);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
          child: Row(
            children: [
              Icon(warn ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  size: 14, color: warn ? cs.error : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: warn ? cs.error : cs.onSurfaceVariant)),
              ),
              if (ask)
                TextButton(
                  onPressed: chat.allowOpen,
                  child: Text(ruEn('Разрешить', 'Allow')),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      ruEn('Здесь будет ваша переписка и что вы делали с видео: кто включил, поставил паузу, перемотал.',
                          'Your chat and what you both do with the video — who started, paused or skipped — show up here.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[items.length - 1 - i];
                    return it.m != null ? _bubble(it.m!, cs) : _event(it.l!, cs);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('fork-room-input'),
                    controller: _input,
                    enabled: usable,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      hintText: ruEn('Написать партнёру…', 'Message your partner…'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  key: const ValueKey('fork-room-send'),
                  tooltip: ruEn('Отправить', 'Send'),
                  onPressed: usable && !_sending ? _send : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubble(RoomMessage m, ColorScheme cs) => Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: m.mine ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Вдвоём имя не нужно; подписываем только открытые реплики
              // (в комнате браузер, и это может быть не партнёр).
              if (!m.mine && m.open && m.name.isNotEmpty)
                Text(m.name, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              Text(m.text, style: TextStyle(color: m.mine ? cs.onPrimaryContainer : cs.onSurface)),
            ],
          ),
        ),
      );

  static IconData _eventIcon(String kind) => switch (kind) {
        'play' => Icons.play_arrow_rounded,
        'pause' || 'pauseNow' => Icons.pause_rounded,
        'seek' => Icons.fast_forward_rounded,
        'source' => Icons.movie_creation_outlined,
        'here' => Icons.login_rounded,
        'gone' => Icons.logout_rounded,
        'countdown' => Icons.timer_3_rounded,
        _ => Icons.info_outline_rounded,
      };

  Widget _event(ForkRoomLine l, ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_eventIcon(l.kind), size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l.text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
}
