import 'dart:convert';
import 'dart:typed_data';

import 'package:pocketbase/pocketbase.dart';

import '../e2e/crypto.dart';

/// A broker publication cannot acquire server authority by naming a collection.
/// The public key comes from our HTTPS API; no secret is shared with clients.
class ForkVerifiedDelta {
  ForkVerifiedDelta(this.pb, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final PocketBase pb;
  final DateTime Function() _now;
  static final _instances = Expando<ForkVerifiedDelta>();
  static final Future<E2ECrypto> _crypto = E2ECrypto.init();
  static ForkVerifiedDelta forBackend(PocketBase pb) =>
      _instances[pb] ??= ForkVerifiedDelta(pb);

  Future<Uint8List>? _key;
  DateTime? _keyAt;
  final Map<String, int> _seen = {};

  static String signalChannel(String channel) {
    if (channel.startsWith('pair:')) return 'signal:${channel.substring(5)}';
    if (channel.startsWith('loc:')) return 'locsignal:${channel.substring(4)}';
    return channel;
  }

  Future<Uint8List> _publicKey() async {
    if (_keyAt == null ||
        _now().difference(_keyAt!) > const Duration(minutes: 1)) {
      _keyAt = _now();
      _key = () async {
        final data = await pb.send('/api/fork/realtime-key');
        if (data is! Map ||
            data['v'] != 1 ||
            data['alg'] != 'Ed25519' ||
            data['key'] is! String ||
            (data['key'] as String).length > 44) {
          throw const FormatException('Invalid realtime key');
        }
        final key = unb64(data['key'] as String);
        if (key.length != 32)
          throw const FormatException('Invalid realtime key');
        return key;
      }();
    }
    return _key!;
  }

  Future<Map<String, dynamic>?> open(
    String channel,
    Map<String, dynamic> envelope,
  ) async {
    try {
      final at = envelope['at'], nonce = envelope['nonce'];
      final payload = envelope['payload'], signature = envelope['sig'];
      final now = _now().millisecondsSinceEpoch;
      if (envelope['v'] != 1 ||
          envelope['channel'] != channel ||
          at is! int ||
          at > now + 30000 ||
          at < now - 600000 ||
          nonce is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce) ||
          payload is! String ||
          payload.length > 16 << 20 ||
          signature is! String ||
          signature.length > 88 ||
          _seen.containsKey(nonce))
        return null;
      final key = await _publicKey();
      final crypto = await _crypto;
      final message = Uint8List.fromList(
        utf8.encode('tethered-realtime-v1\n$channel\n$at\n$nonce\n$payload'),
      );
      if (!crypto.verify(message, unb64(signature), key)) return null;
      // Concurrent verification of the same packet must still deliver once.
      _seen.removeWhere((_, seenAt) => seenAt < now - 600000);
      if (_seen.containsKey(nonce) || _seen.length >= 8192) return null;
      final decoded = jsonDecode(utf8.decode(unb64(payload)));
      if (decoded is! Map<String, dynamic>) return null;
      _seen[nonce] = at;
      return decoded;
    } on Object {
      return null; // no unsigned fallback on unavailable key or bad signature
    }
  }
}
