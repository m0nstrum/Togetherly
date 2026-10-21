// fork: голос только через свой TURN (lib/fork/ice_policy.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ice_policy.dart';

void main() {
  test('есть TURN — только relay', () {
    final c = forkPeerConfig([
      {
        'urls': ['stun:t.example.org:3478'],
      },
      {
        'urls': ['turn:t.example.org:3478?transport=udp'],
        'username': 'u',
        'credential': 'p',
      },
    ]);
    expect(c['iceTransportPolicy'], 'relay');
    expect(c['sdpSemantics'], 'unified-plan');
  });

  test('url строкой тоже понимаем', () {
    final c = forkPeerConfig([
      {'urls': 'turn:t.example.org:3478'},
    ]);
    expect(c['iceTransportPolicy'], 'relay');
  });

  test('без TURN — прямое соединение, как у апстрима', () {
    expect(forkPeerConfig([]).containsKey('iceTransportPolicy'), isFalse);
    expect(
      forkPeerConfig([
        {'urls': 'stun:t.example.org:3478'},
      ]).containsKey('iceTransportPolicy'),
      isFalse,
    );
  });
}
