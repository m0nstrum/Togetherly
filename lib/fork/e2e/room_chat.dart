/// Чат комнаты «Смотрим вместе» на ключе сессии (docs/fork/E2E.md §10.1).
///
/// Страница комнаты в приложении — только плеер, переписку держит
/// приложение. Ключ сессии `RK` — 32 случайных байта: заводит первое
/// приложение в комнате, живёт он только в памяти и стирается с концом
/// сессии. С ключами пары и аккаунта `RK` не связан: ключ пары лишь
/// перевозит его по каналу комнаты (`rk`), так что подменённая сервером
/// страница не вскроет ни прошлые сеансы, ни остальные данные пары.
///
/// Протокол поверх канала `watch:<комната>` (страница эти типы пропускает):
/// - `rk?` — «у кого ключ?»; `rk` — ключ сессии под ключом пары;
/// - `chat` с `e2e` — реплика под `RK`; без `e2e` — открытая реплика
///   браузера или приложения рядом с браузером;
/// - `log` — переписка этой сессии для вошедшего позже, под `RK`;
/// - `hello` с `web: true` — в комнате вкладка браузера.
///
/// Пока в комнате есть браузер, приложения пишут открыто и показывают
/// «в браузере переписка видна серверу» (решение §12.3).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'crypto.dart';
import 'envelope.dart';
import 'record_codec.dart';

/// Канал комнаты: отправить сообщение и слушать чужие (свои отсекает сам).
abstract interface class RoomTransport {
  Future<void> send(Map<String, dynamic> msg);
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  );
}

class RoomMessage {
  const RoomMessage({
    required this.from,
    required this.name,
    required this.text,
    required this.at,
    required this.mine,
    required this.open,
  });

  final String from;
  final String name;
  final String text;
  final int at;
  final bool mine;

  /// Шло открытым текстом (браузер в комнате).
  final bool open;

  Map<String, dynamic> toJson() => {
    'from': from,
    'name': name,
    'text': text,
    'at': at,
  };
}

/// Ключи сессии и пары под интерфейсом кодека.
class _Keys implements E2EKeyring {
  _Keys(this.pair);

  final E2EKeyring pair;
  final Map<String, PairKey> session = {};

  @override
  PairKey? keyFor(String keyId) => session[keyId] ?? pair.keyFor(keyId);
  @override
  PairKey? currentKey(String groupId) => pair.currentKey(groupId);
  @override
  String? groupWith(Set<String> members) => pair.groupWith(members);
}

class RoomChat extends ChangeNotifier {
  RoomChat({
    required this.room,
    required this.groupId,
    required this.me,
    required this.name,
    required E2ECrypto crypto,
    required E2EKeyring pairKeys,
    required RoomTransport transport,
    this.keyWait = const Duration(milliseconds: 1500),
  }) : _c = crypto,
       _keys = _Keys(pairKeys),
       _t = transport {
    _codec = RecordCodec(_c, _keys);
  }

  final String room;
  final String groupId;
  final String me;
  final String name;
  final Duration keyWait;
  final E2ECrypto _c;
  final _Keys _keys;
  final RoomTransport _t;
  late final RecordCodec _codec;

  static const int logLimit = 50;

  String get channel => 'watch:$room';

  final List<RoomMessage> messages = [];

  /// В комнате вкладка браузера (или кто-то пишет открыто). Сам по себе
  /// ничего не включает: сервер может подделать и то и другое.
  bool browser = false;

  /// Человек сам разрешил открытый чат с браузером ([allowOpen]).
  bool openAllowed = false;

  PairKey? _rk;
  String _rkId = '';
  Future<void> Function()? _stop;
  Timer? _wait;
  bool _closed = false;

  /// Переписка шифруется ключом сессии.
  bool get secure => _rk != null && !openMode;

  /// Ключа пары нет — партнёры ещё не обменялись ключами, сеансовому ключу
  /// не на чем ехать: чата нет.
  bool get noPairKey => _keys.currentKey(groupId) == null;

  /// Пишем открыто: в комнате браузер, и человек на это согласился.
  bool get openMode => browser && openAllowed;

  /// Согласие на открытый чат с браузером — до конца сессии.
  void allowOpen() {
    if (openAllowed) return;
    openAllowed = true;
    notifyListeners();
  }

  Future<void> start() async {
    final stop = await _t.listen(_onMessage);
    if (_closed) {
      // Комнату закрыли, пока подписывались.
      await stop();
      return;
    }
    _stop = stop;
    if (noPairKey) return;
    await _t.send({'t': 'rk?', 'from': me});
    _wait = Timer(keyWait, () {
      if (_rk == null && !_closed) unawaited(_newKey());
    });
  }

  @override
  void dispose() {
    _closed = true;
    _wait?.cancel();
    final stop = _stop;
    _stop = null;
    if (stop != null) unawaited(stop());
    // Ключ сессии живёт только пока открыта комната.
    for (final k in _keys.session.values) {
      k.key.dispose();
    }
    _keys.session.clear();
    _rk = null;
    super.dispose();
  }

  Future<void> _newKey() async {
    final id = b64(_c.random(9));
    _adopt(id, _c.symmetricKey());
    await _announce();
  }

  void _adopt(String id, SecureKey key) {
    // Прежний ключ сессии остаётся до конца: им могли успеть написать.
    _rkId = id;
    _rk = PairKey('rk-$id', 1, key);
    _keys.session[_rk!.keyId] = _rk!;
    notifyListeners();
  }

  ChannelPlace _place(String type, String from, int at) =>
      ChannelPlace(channel, '$type:$from', at);

  Future<void> _announce() async {
    final rk = _rk;
    final pk = _keys.currentKey(groupId);
    if (rk == null || pk == null) return;
    await _t.send({
      't': 'rk',
      'from': me,
      'e2e': _codec.sealChannel(_place('rk', me, 0), {
        'id': _rkId,
        'k': b64(rk.key.extractBytes()),
      }, pk),
    });
    if (messages.isNotEmpty) {
      final at = DateTime.now().millisecondsSinceEpoch;
      await _t.send({
        't': 'log',
        'from': me,
        'ts': at,
        'e2e': _codec.sealChannel(_place('log', me, at), {
          'log': [
            for (final m in messages.reversed.take(logLimit).toList().reversed)
              m.toJson(),
          ],
        }, rk),
      });
    }
  }

  void _onMessage(Map<String, dynamic> m) {
    if (_closed) return;
    final from = '${m['from'] ?? ''}';
    if (from.isEmpty || from == me) return;
    switch (m['t']) {
      case 'hello':
        if (m['web'] == true) _setBrowser();
        if (_rk != null) unawaited(_announce());
      case 'rk?':
        if (_rk != null) unawaited(_announce());
      case 'rk':
        final open = m['e2e'] is String
            ? _codec.openChannel(_place('rk', from, 0), m['e2e'] as String)
            : null;
        final id = open?['id'], k = open?['k'];
        if (id is! String || k is! String) return;
        // Двое завели ключ одновременно: оба берут меньший id. Свой меньше —
        // напоминаем о нём: тот мог пропустить наше объявление.
        if (_rk != null && _rkId.compareTo(id) <= 0) {
          if (_rkId != id) unawaited(_announce());
          return;
        }
        _wait?.cancel();
        _adopt(id, _c.keyFromBytes(unb64(k)));
      case 'chat':
        _onChat(from, m);
      case 'log':
        _onLog(from, m);
    }
  }

  void _setBrowser() {
    if (browser) return;
    browser = true;
    notifyListeners();
  }

  void _onChat(String from, Map<String, dynamic> m) {
    final sealed = m['e2e'];
    if (sealed is! String) {
      // Открытая реплика: её пишет браузер или приложение рядом с ним — или
      // сервер. Показываем, только если человек разрешил открытый чат.
      _setBrowser();
      if (!openMode) return;
      final text = '${m['text'] ?? ''}';
      if (text.isEmpty) return;
      _add(
        RoomMessage(
          from: from,
          name: '${m['name'] ?? ''}',
          text: text,
          at: DateTime.now().millisecondsSinceEpoch,
          mine: false,
          open: true,
        ),
      );
      return;
    }
    final at = m['ts'] is int ? m['ts'] as int : 0;
    final open = _codec.openChannel(_place('chat', from, at), sealed);
    if (open == null) return;
    _add(
      RoomMessage(
        from: from,
        name: '${open['name'] ?? ''}',
        text: '${open['text'] ?? ''}',
        at: at,
        mine: false,
        open: false,
      ),
    );
  }

  void _onLog(String from, Map<String, dynamic> m) {
    if (messages.isNotEmpty) return;
    final sealed = m['e2e'];
    final at = m['ts'] is int ? m['ts'] as int : 0;
    if (sealed is! String) return;
    final open = _codec.openChannel(_place('log', from, at), sealed);
    final log = open?['log'];
    if (log is! List) return;
    for (final e in log.whereType<Map<String, dynamic>>()) {
      final who = '${e['from'] ?? ''}';
      messages.add(
        RoomMessage(
          from: who,
          name: '${e['name'] ?? ''}',
          text: '${e['text'] ?? ''}',
          at: e['at'] is int ? e['at'] as int : 0,
          mine: who == me,
          open: false,
        ),
      );
    }
    notifyListeners();
  }

  void _add(RoomMessage m) {
    messages.add(m);
    if (messages.length > logLimit * 4) messages.removeAt(0);
    notifyListeners();
  }

  /// Отправить реплику. false — ключ сессии ещё не договорён (первые
  /// полторы секунды в комнате).
  Future<bool> send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final at = DateTime.now().millisecondsSinceEpoch;
    final rk = _rk;
    if (noPairKey) return false;
    if (openMode) {
      await _t.send({'t': 'chat', 'from': me, 'text': t, 'name': name});
    } else if (rk != null) {
      await _t.send({
        't': 'chat',
        'from': me,
        'ts': at,
        'e2e': _codec.sealChannel(_place('chat', me, at), {
          'text': t,
          'name': name,
        }, rk),
      });
    } else {
      return false;
    }
    _add(
      RoomMessage(
        from: me,
        name: name,
        text: t,
        at: at,
        mine: true,
        open: openMode,
      ),
    );
    return true;
  }
}
