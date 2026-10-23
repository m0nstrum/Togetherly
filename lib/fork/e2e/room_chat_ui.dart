/// Нативный чат комнаты поверх плеера (docs/fork/E2E.md §10.1).
///
/// Кнопка в углу со счётчиком непрочитанного и панель переписки. Строка
/// сверху честно говорит, видит ли переписку сервер.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/centrifugo_service.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import 'fork_e2e.dart';
import 'room_chat.dart';

bool get _ru => const {
  'ru',
  'uk',
  'be',
}.contains(LocaleService.instance.language.code.toLowerCase());

String _t(String ru, String en) => _ru ? ru : en;

/// Канал комнаты через общий клиент Centrifugo.
class CentrifugoRoomTransport implements RoomTransport {
  CentrifugoRoomTransport(this.channel);

  final String channel;

  @override
  Future<void> send(Map<String, dynamic> msg) async {
    await CentrifugoService.instance.publish(
      channel,
      msg,
      requireDelivery: msg['t'] == 'chat',
    );
  }

  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  ) async {
    final unsub = await CentrifugoService.instance.subscribeRaw(
      channel,
      onMessage,
    );
    return () async => unsub();
  }
}

/// Скрипт для страницы комнаты: чат держит приложение.
const String forkNativeChatScript = 'window.__forkNativeChat=true;';

/// Чат комнаты на ключе сессии: null — шифрования ещё нет (нет ключей или
/// входа). Запущен; освобождает тот, кто создал.
Future<RoomChat?> forkStartRoomChat(String room, String groupId) async {
  final codec = await ForkE2E.codec();
  final c = codec?.crypto;
  final me = PocketBaseService().userId ?? '';
  if (codec == null || c == null || me.isEmpty) return null;
  final chat = RoomChat(
    room: room,
    groupId: groupId,
    me: me,
    name: PocketBaseService().userName,
    crypto: c,
    pairKeys: codec.keys,
    transport: CentrifugoRoomTransport('watch:$room'),
  );
  unawaited(chat.start());
  return chat;
}

/// Строка о шифровании над перепиской.
String forkRoomChatStatus(RoomChat chat) {
  if (chat.noPairKey) {
    return _t(
      'Ключи пары ещё не обменялись — чат недоступен',
      'Pair keys are not exchanged yet — chat is unavailable',
    );
  }
  if (chat.openMode) {
    return _t(
      'Открытый чат с браузером: переписку видит сервер',
      'Open chat with a browser: the server can read it',
    );
  }
  if (chat.browser) {
    return _t(
      'В комнате браузер: его реплики не видны, пока вы не разрешите открытый чат',
      'A browser is in the room: its messages stay hidden until you allow open chat',
    );
  }
  if (!chat.secure) {
    return _t('Договариваемся о ключе…', 'Agreeing on a key…');
  }
  return _t(
    'Переписка зашифрована ключом этого сеанса',
    'Chat is encrypted with this session’s key',
  );
}

class ForkRoomChatOverlay extends StatefulWidget {
  const ForkRoomChatOverlay({
    super.key,
    required this.room,
    required this.groupId,
    this.chat,
  });

  final String room;
  final String groupId;

  /// Готовый чат вместо своего: его держит экран комнаты (одна переписка на
  /// вертикальную раскладку и на полный экран) или тест.
  final RoomChat? chat;

  @override
  State<ForkRoomChatOverlay> createState() => _ForkRoomChatOverlayState();
}

class _ForkRoomChatOverlayState extends State<ForkRoomChatOverlay> {
  RoomChat? _chat;
  bool _open = false;
  int _seen = 0;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final given = widget.chat;
    if (given != null) {
      setState(() => _chat = given..addListener(_changed));
      return;
    }
    final chat = await forkStartRoomChat(widget.room, widget.groupId);
    if (chat == null) return;
    if (!mounted) {
      chat.dispose();
      return;
    }
    chat.addListener(_changed);
    setState(() => _chat = chat);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_open) _seen = _chat?.messages.length ?? 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _chat?.removeListener(_changed);
    // Переданный снаружи чат освобождает его владелец.
    if (widget.chat == null) _chat?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chat = _chat;
    if (chat == null || !chat.canSend || _input.text.trim().isEmpty) return;
    final text = _input.text;
    _input.clear();
    await chat.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    if (chat == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final unread = _open ? 0 : chat.messages.length - _seen;
    if (!_open) {
      return Positioned(
        right: 12,
        bottom: 12 + MediaQuery.paddingOf(context).bottom,
        child: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: FloatingActionButton.small(
            heroTag: 'fork-room-chat',
            tooltip: _t('Чат', 'Chat'),
            onPressed: () => setState(() {
              _open = true;
              _seen = chat.messages.length;
            }),
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      );
    }
    final warn = !chat.secure;
    final ask = chat.browser && !chat.openAllowed && !chat.noPairKey;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8 + MediaQuery.viewInsetsOf(context).bottom,
      height: MediaQuery.sizeOf(context).height * 0.42,
      child: Material(
        elevation: 6,
        color: cs.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
              child: Row(
                children: [
                  Icon(
                    warn ? Icons.lock_open : Icons.lock_outline,
                    size: 16,
                    color: warn ? cs.error : cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      forkRoomChatStatus(chat),
                      style: TextStyle(
                        fontSize: 12,
                        color: warn ? cs.error : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (ask)
                    TextButton(
                      onPressed: chat.allowOpen,
                      child: Text(_t('Разрешить', 'Allow')),
                    ),
                  IconButton(
                    tooltip: _t('Свернуть', 'Hide'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _open = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: chat.messages.isEmpty
                  ? Center(
                      child: Text(
                        _t('Сообщений пока нет', 'No messages yet'),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: chat.messages.length,
                      itemBuilder: (_, i) => _bubble(chat.messages[i], cs),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: chat.canSend,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_send()),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: chat.canSend
                            ? _t('Сообщение', 'Message')
                            : forkRoomChatStatus(chat),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Отправить', 'Send'),
                    icon: const Icon(Icons.send),
                    onPressed: chat.canSend ? () => unawaited(_send()) : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool chatCanRetry(RoomMessage m) => _chat?.canSend == true && !m.pending;

  Widget _bubble(RoomMessage m, ColorScheme cs) => Align(
    alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: m.mine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!m.mine && m.name.isNotEmpty)
            Text(
              m.name,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          Text(m.text),
          if (m.pending)
            Text(
              _t('Отправляем…', 'Sending…'),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          if (m.failed)
            TextButton.icon(
              onPressed: chatCanRetry(m)
                  ? () => unawaited(_chat!.retry(m))
                  : null,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_t('Не отправлено · Повторить', 'Not sent · Retry')),
            ),
        ],
      ),
    ),
  );
}
