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
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final String group, me, partner;
  final RecordCodec codec;
  final RoomTransport transport;
  final Future<void> Function() vibrate;
  final bool Function() allowed;
  final DateTime Function() now;
  static const freshness = Duration(seconds: 2);
  Offset? mine, peer;
  bool ready = false, failed = false, matched = false;
  bool _closed = false, _sending = false, _dirty = false;
  int _sentAt = 0, _peerAt = 0, _lastMoveAt = 0;
  DateTime? _peerSeen;
  Timer? _pulse;
  Future<void> Function()? _unsub;
  String get channel => 'pair:$group';
  bool get canTouch =>
      ready && allowed() && codec.keys.currentKey(group) != null;
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
    if (!canTouch) {
      mine = null;
      peer = null;
    } else if (_peerSeen != null && now().difference(_peerSeen!) >= freshness) {
      peer = null;
    }
    if (mine != null) _queue(); // Renew a held finger even when it is still.
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
        (now().millisecondsSinceEpoch - at).abs() > freshness.inMilliseconds) {
      return;
    }
    final data = codec.openChannel(_place(partner, at), sealed);
    if (data == null || data['down'] is! bool) return;
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
    _peerAt = at;
    _peerSeen = now();
    peer = position;
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
      final key = codec.keys.currentKey(group)!;
      final at = math.max(now().millisecondsSinceEpoch, _sentAt + 1);
      _sentAt = at;
      final point = mine;
      try {
        await transport.send({
          't': 'fork-touch',
          'from': me,
          'at': at,
          'e2e': codec.sealChannel(_place(me, at), {
            'down': point != null,
            if (point != null) 'x': point.dx,
            if (point != null) 'y': point.dy,
          }, key),
        });
        failed = false;
      } catch (_) {
        failed = true;
        peer = null;
        matched = false;
      }
      if (!_closed) notifyListeners();
    }
    _sending = false;
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
    _closed = true;
    _pulse?.cancel();
    final unsub = _unsub;
    if (unsub != null) unawaited(unsub().catchError((Object _) {}));
    super.dispose();
  }
}
