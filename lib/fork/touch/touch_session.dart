/// Ephemeral pair touch: authenticated coordinates, no database history.
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import '../e2e/envelope.dart';
import '../e2e/record_codec.dart';
import '../e2e/room_chat.dart' show RoomTransport;

class ForkTouchSession extends ChangeNotifier {
  ForkTouchSession({
    required this.group,
    required this.me,
    required this.partner,
    required this.codec,
    required this.transport,
    required this.vibrate,
    required this.allowed,
    bool Function()? linkUp,
    this.onPartnerSeen,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       linkUp = linkUp ?? _always;
  final String group, me, partner;
  final RecordCodec codec;
  final RoomTransport transport;
  final Future<void> Function() vibrate;
  final bool Function() allowed;
  final DateTime Function() now;

  /// Своя связь есть: сокет поднят и подписка на канал пары стоит.
  final bool Function() linkUp;

  /// Проверенный пакет партнёра — признак жизни для присутствия (B10).
  final void Function()? onPartnerSeen;
  static bool _always() => true;
  static const freshness = Duration(seconds: 2);

  /// Пока экран открыт, раз в [here] уходит «я здесь» (без пальца — пакет
  /// `down: false`). Так второй телефон отличает «партнёр не на экране» от
  /// «партнёр тут, но не касается».
  static const here = Duration(seconds: 3);

  /// Партнёр на экране, если его пакет моложе [away]: два пропущенных «я
  /// здесь» ещё не уход.
  static const away = Duration(seconds: 8);

  /// «Нет связи» — только если своей связи нет дольше [linkGrace] (B11).
  /// Подписка после переподключения встаёт за секунду-две, и мигать
  /// надписью на каждом таком круге незачем.
  static const linkGrace = Duration(seconds: 3);

  /// Phone clocks are not synced: [freshness] is measured by receipt time,
  /// the sender's stamp only has to be roughly current and increasing.
  static const clockSkew = Duration(minutes: 2);
  Offset? mine, peer;
  bool ready = false, failed = false, matched = false;
  bool _closed = false, _sending = false, _dirty = false;
  int _sentAt = 0, _peerAt = 0, _lastMoveAt = 0;
  DateTime? _peerSeen, _downSince, _failedSince;
  Timer? _pulse;
  Future<void> Function()? _unsub;
  String get channel => 'pair:$group';
  bool get canTouch =>
      ready && allowed() && codec.keys.currentKey(group) != null;

  /// Своей связи нет (B11). Раньше «нет связи» показывалось по [failed] —
  /// по одной неудачной отправке, — и висело, пока человек не коснётся
  /// экрана снова: повторять было некому. Теперь — по состоянию сокета и
  /// подписки, а неудача отправки считается, только если не проходит
  /// повтор дольше [linkGrace].
  bool get offline => _stale(_downSince) || _stale(_failedSince);

  bool _stale(DateTime? since) =>
      since != null && now().difference(since) >= linkGrace;

  /// Партнёр сейчас на экране прикосновения.
  bool get partnerHere =>
      _peerSeen != null && now().difference(_peerSeen!) < away;
  ChannelPlace _place(String from, int at) =>
      ChannelPlace(channel, 'fork-touch:$from', at);

  Future<void> start() async {
    if (ready || _closed) return;
    try {
      if (!allowed() || codec.keys.currentKey(group) == null) {
        throw StateError('Pair key unavailable');
      }
      final unsub = await transport.listen(receive);
      if (_closed) {
        await unsub();
        return;
      }
      _unsub = unsub;
      ready = true;
      _pulse = Timer.periodic(const Duration(milliseconds: 400), (_) => tick());
      _queue(); // «я здесь» — сразу, а не через [here]
    } catch (_) {
      failed = true;
    }
    if (!_closed) notifyListeners();
  }

  /// Normalized coordinates use the same square on both phones.
  void point(Offset? value) {
    if (_closed) return;
    mine = canTouch && value != null
        ? Offset(value.dx.clamp(0, 1), value.dy.clamp(0, 1))
        : null;
    final at = now().millisecondsSinceEpoch;
    if (mine == null || at - _lastMoveAt >= 100) {
      _lastMoveAt = at;
      _queue();
    }
    _match();
    notifyListeners();
  }

  void tick() {
    if (_closed) return;
    if (linkUp()) {
      _downSince = null;
    } else {
      _downSince ??= now();
    }
    if (!canTouch) {
      mine = null;
      peer = null;
    } else if (_peerSeen != null && now().difference(_peerSeen!) >= freshness) {
      peer = null;
    }
    // Держит палец — обновляем точку; нет — «я здесь» раз в [here]; не
    // ушло — повторяем, а не ждём нового касания.
    if (mine != null ||
        failed ||
        now().millisecondsSinceEpoch - _sentAt >= here.inMilliseconds) {
      _queue();
    }
    _match();
    notifyListeners();
  }

  void receive(Map<String, dynamic> packet) {
    if (_closed ||
        !canTouch ||
        packet['t'] != 'fork-touch' ||
        packet['from'] != partner) {
      return;
    }
    final at = packet['at'], sealed = packet['e2e'];
    if (at is! int ||
        at <= _peerAt ||
        sealed is! String ||
        sealed.length > 4096 ||
        (now().millisecondsSinceEpoch - at).abs() > clockSkew.inMilliseconds) {
      return;
    }
    final data = codec.openChannel(_place(partner, at), sealed);
    if (data == null || data['down'] is! bool) return;
    onPartnerSeen?.call();
    if (data['bye'] == true) {
      // Партнёр закрыл экран: не ждём восьми секунд тишины.
      _peerAt = at;
      _peerSeen = null;
      peer = null;
      _match();
      notifyListeners();
      return;
    }
    Offset? position;
    if (data['down'] == true) {
      final x = data['x'], y = data['y'];
      if (x is! num ||
          y is! num ||
          !x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          x > 1 ||
          y < 0 ||
          y > 1) {
        return;
      }
      position = Offset(x.toDouble(), y.toDouble());
    }
    final arrived = !partnerHere;
    _peerAt = at;
    _peerSeen = now();
    peer = position;
    // Партнёр только что пришёл — отзываемся сразу, чтобы и он увидел нас без
    // ожидания. Только на приход: двое не перебрасываются ответами.
    if (arrived) _queue();
    _match();
    notifyListeners();
  }

  void _match() {
    final next =
        !failed &&
        canTouch &&
        mine != null &&
        peer != null &&
        (mine! - peer!).distance <= .09;
    if (next && !matched) unawaited(vibrate().catchError((Object _) {}));
    matched = next;
  }

  void _queue() {
    if (!canTouch || _closed) return;
    _dirty = true;
    if (!_sending) unawaited(_flush());
  }

  Future<void> _flush() async {
    _sending = true;
    while (_dirty && !_closed && canTouch) {
      _dirty = false;
      try {
        await transport.send(_packet(mine));
        failed = false;
        _failedSince = null;
      } catch (_) {
        failed = true;
        _failedSince ??= now();
        peer = null;
        matched = false;
      }
      if (!_closed) notifyListeners();
    }
    _sending = false;
  }

  Map<String, dynamic> _packet(Offset? point, {bool bye = false}) {
    final key = codec.keys.currentKey(group)!;
    final at = math.max(now().millisecondsSinceEpoch, _sentAt + 1);
    _sentAt = at;
    return {
      't': 'fork-touch',
      'from': me,
      'at': at,
      'e2e': codec.sealChannel(_place(me, at), {
        'down': point != null,
        if (point != null) 'x': point.dx,
        if (point != null) 'y': point.dy,
        // Сборки постарше лишнего поля не видят: для них это просто «отпустил».
        if (bye) 'bye': true,
      }, key),
    };
  }

  /// Inactive routes never keep a finger down. Peer expiry handles lost ups.
  void suspend() {
    point(null);
    peer = null;
    matched = false;
    notifyListeners();
  }

  @override
  void dispose() {
    suspend();
    if (canTouch) {
      // «Ушёл с экрана» — партнёр сразу видит, что звать надо снова.
      unawaited(
        transport
            .send(_packet(null, bye: true))
            .catchError((Object _) {}), // тихо: уходим, повторять некому
      );
    }
    _closed = true;
    _pulse?.cancel();
    final unsub = _unsub;
    if (unsub != null) unawaited(unsub().catchError((Object _) {}));
    super.dispose();
  }
}
