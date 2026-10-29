import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pocketbase/pocketbase.dart';

import '../e2e/crypto.dart';

/// A broker publication cannot acquire server authority by naming a collection.
/// The public key comes from our HTTPS API; no secret is shared with clients.
class ForkVerifiedDelta {
  ForkVerifiedDelta(this.pb);
  final PocketBase pb;
  static final _instances = Expando<ForkVerifiedDelta>();
  static final Future<E2ECrypto> _crypto = E2ECrypto.init();
  static ForkVerifiedDelta forBackend(PocketBase pb) =>
      _instances[pb] ??= ForkVerifiedDelta(pb);

  Future<Uint8List>? _key;
  final Stopwatch _keyAge = Stopwatch();
  int? _serverTime;
  final ReplayWindow _replay = ReplayWindow();

  /// Каналы, чьи дельты отброшены из-за недоступного ключа (RT-3). Дельта без
  /// проверки подписи не принимается никогда (fail closed), но пропущенное
  /// надо догнать с сервера, когда ключ вернётся.
  final Set<String> _starved = {};
  Timer? _keyRetry;
  int _keyRetryAttempt = 0;

  static final StreamController<String> _keyRecovered =
      StreamController<String>.broadcast();

  /// Ключ подписи снова получен: канал, дельты которого отбрасывались, —
  /// повод догнать его области (`SyncCoordinator`).
  static Stream<String> get keyRecovered => _keyRecovered.stream;

  /// A reconnect may follow sleep, a network outage or server key rotation.
  void refreshKey() {
    _key = null;
    _keyAge.reset();
  }

  static String signalChannel(String channel) {
    if (channel.startsWith('pair:')) return 'signal:${channel.substring(5)}';
    if (channel.startsWith('loc:')) return 'locsignal:${channel.substring(4)}';
    return channel;
  }

  Future<Uint8List> _publicKey() async {
    if (_key == null || _keyAge.elapsed > const Duration(minutes: 1)) {
      _keyAge
        ..reset()
        ..start();
      _key = () async {
        final data = await pb
            .send('/api/fork/realtime-key')
            .timeout(const Duration(seconds: 8));
        if (data is! Map ||
            data['v'] != 1 ||
            data['alg'] != 'Ed25519' ||
            data['time'] is! int ||
            data['key'] is! String ||
            (data['key'] as String).length > 44) {
          throw const FormatException('Invalid realtime key');
        }
        final key = unb64(data['key'] as String);
        if (key.length != 32)
          throw const FormatException('Invalid realtime key');
        _serverTime = data['time'] as int;
        _keyAge
          ..reset()
          ..start();
        _onKeyBack();
        return key;
      }();
    }
    return _key!;
  }

  void _onKeyBack() {
    _keyRetry?.cancel();
    _keyRetry = null;
    _keyRetryAttempt = 0;
    if (_starved.isEmpty) return;
    final channels = _starved.toList();
    _starved.clear();
    for (final c in channels) {
      _keyRecovered.add(c);
    }
  }

  /// Дельта [channel] отброшена без ключа. Новых дельт может и не прийти, а
  /// сам ключ без запроса не вернётся — поэтому пробуем его сами, с паузой
  /// 5, 10, 20, 40 с и дальше раз в минуту, пока не получится.
  void _starve(String channel) {
    _starved.add(channel);
    if (_keyRetry != null) return;
    final seconds = 5 << (_keyRetryAttempt > 3 ? 3 : _keyRetryAttempt);
    _keyRetryAttempt++;
    _keyRetry = Timer(Duration(seconds: seconds > 60 ? 60 : seconds), () {
      _keyRetry = null;
      if (_starved.isEmpty) return;
      _key = null;
      unawaited(
        _publicKey().then<void>(
          (_) {},
          onError: (Object _) {
            if (_starved.isNotEmpty) _starve(_starved.first);
          },
        ),
      );
    });
  }

  Future<Map<String, dynamic>?> open(
    String channel,
    Map<String, dynamic> envelope,
  ) async {
    try {
      final at = envelope['at'], nonce = envelope['nonce'];
      final payload = envelope['payload'], signature = envelope['sig'];
      if (envelope['v'] != 1 ||
          envelope['channel'] != channel ||
          at is! int ||
          nonce is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce) ||
          payload is! String ||
          payload.length > 16 << 20 ||
          signature is! String ||
          signature.length > 88 ||
          _replay.contains(nonce))
        return null;
      final Uint8List key;
      try {
        key = await _publicKey();
      } on Object {
        _starve(channel);
        return null; // fail closed: без ключа дельту не принимаем
      }
      final crypto = await _crypto;
      // HTTPS time plus monotonic elapsed time tolerates a mis-set phone clock.
      final now = _serverTime! + _keyAge.elapsedMilliseconds;
      if (at > now + 30000 || at < now - 600000) return null;
      final message = Uint8List.fromList(
        utf8.encode('tethered-realtime-v1\n$channel\n$at\n$nonce\n$payload'),
      );
      if (!crypto.verify(message, unb64(signature), key)) return null;
      final decoded = jsonDecode(utf8.decode(unb64(payload)));
      if (decoded is! Map<String, dynamic>) return null;
      // Concurrent verification of the same packet must still deliver once.
      if (!_replay.admit(nonce, at, now)) return null;
      return decoded;
    } on Object {
      return null; // no unsigned fallback on unavailable key or bad signature
    }
  }
}

/// Защита от повторов: nonce помнится, пока пакет свеж (10 минут).
///
/// Раньше при 8192 nonce за окно отбрасывались ВСЕ следующие дельты, пока
/// старые не протухнут (RT-3). Теперь переполнение вытесняет самые ранние, а
/// порог [_floor] поднимается до самого позднего `at` среди вытесненных:
/// пакет не новее порога не принимается. Повтор вытесненного nonce так не
/// пройдёт, а свежие дельты идут дальше.
class ReplayWindow {
  ReplayWindow({this.capacity = 8192, this.window = 600000});

  final int capacity;
  final int window;

  /// nonce → `at`; порядок вставки (LinkedHashMap) — порядок вытеснения.
  final Map<String, int> _seen = {};
  int? _floor;

  int get length => _seen.length;

  bool contains(String nonce) => _seen.containsKey(nonce);

  /// `true` — пакет [nonce] видим впервые, и он запомнен.
  bool admit(String nonce, int at, int now) {
    _seen.removeWhere((_, seenAt) => seenAt < now - window);
    if (_seen.containsKey(nonce)) return false;
    final floor = _floor;
    if (floor != null && at <= floor) return false;
    while (_seen.length >= capacity) {
      final oldest = _seen.keys.first;
      final evictedAt = _seen.remove(oldest)!;
      if (_floor == null || evictedAt > _floor!) _floor = evictedAt;
    }
    _seen[nonce] = at;
    return true;
  }
}
