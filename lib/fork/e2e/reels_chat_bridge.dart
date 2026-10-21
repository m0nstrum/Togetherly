/// Чат ленты вдвоём на ключе сессии (docs/fork/E2E.md §10.1).
///
/// Лента рисует переписку сама — реплики поверх ролика и лист чата, — и
/// менять это незачем. Но страница слала реплики открытым текстом через
/// сервер. Теперь с `window.__forkNativeChat` она отдаёт текст приложению
/// (`forkChat`), а приложение шифрует его [RoomChat] и возвращает странице
/// всю переписку, свою и партнёра, вызовом `window.forkChatIn`.
library;

import 'dart:async';
import 'dart:convert';

import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import 'fork_e2e.dart';
import 'room_chat.dart';
import 'room_chat_ui.dart' show CentrifugoRoomTransport;

bool get _ru => const {
  'ru',
  'uk',
  'be',
}.contains(LocaleService.instance.language.code.toLowerCase());

String _t(String ru, String en) => _ru ? ru : en;

class ForkReelsChatBridge {
  ForkReelsChatBridge({
    required this.room,
    required this.groupId,
    required this.eval,
    RoomChat? chat,
  }) : _chat = chat;

  final String room;
  final String groupId;

  /// Выполнить JS на странице ленты.
  final Future<void> Function(String js) eval;

  RoomChat? _chat;
  int _pushed = 0;
  String _status = '';
  bool _ready = false;
  bool _disposed = false;

  Future<void> start() async {
    var chat = _chat;
    if (chat == null) {
      final codec = await ForkE2E.codec();
      final c = codec?.crypto;
      final me = PocketBaseService().userId ?? '';
      if (_disposed || codec == null || c == null || me.isEmpty) return;
      chat = RoomChat(
        room: room,
        groupId: groupId,
        me: me,
        name: PocketBaseService().userName,
        crypto: c,
        pairKeys: codec.keys,
        transport: CentrifugoRoomTransport('watch:$room'),
      );
      _chat = chat;
    }
    chat.addListener(_flush);
    await chat.start();
    _flush();
  }

  /// Страница загрузилась: с этого момента ей есть кого слушать.
  void pageReady() {
    _ready = true;
    _pushed = 0;
    _status = '';
    _flush();
  }

  /// Реплика со страницы.
  Future<void> send(String text) async {
    final chat = _chat;
    if (chat == null) return;
    if (!await chat.send(text)) _flush(force: true);
  }

  void _flush({bool force = false}) {
    final chat = _chat;
    if (chat == null || !_ready || _disposed) return;
    final status = _statusOf(chat);
    if (status != _status || force) {
      _status = status;
      _push({'text': status, 'sys': true});
    }
    for (; _pushed < chat.messages.length; _pushed++) {
      final m = chat.messages[_pushed];
      _push({'name': m.name, 'text': m.text, 'mine': m.mine});
    }
  }

  void _push(Map<String, dynamic> m) => unawaited(
    eval('window.forkChatIn && window.forkChatIn(${jsonEncode(m)})'),
  );

  static String _statusOf(RoomChat chat) {
    if (chat.noPairKey) {
      return _t(
        'Ключи пары ещё не обменялись — чат недоступен',
        'Pair keys are not exchanged yet — chat is unavailable',
      );
    }
    if (chat.browser) {
      return _t(
        'В ленте браузер: его реплики скрыты',
        'A browser joined: its messages are hidden',
      );
    }
    if (!chat.secure) return _t('Договариваемся о ключе…', 'Agreeing on a key…');
    return _t(
      '🔒 Чат зашифрован ключом сеанса',
      '🔒 Chat is end-to-end encrypted',
    );
  }

  void dispose() {
    _disposed = true;
    _chat?.removeListener(_flush);
    _chat?.dispose();
  }
}
