import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_channel_service.dart';

/// Комната без сети: что сделал join — видно по счётчикам.
class _FakeRoom extends WatchChannel {
  _FakeRoom({this.connectError, this.onConnected}) : super('r', 'me');

  final Object? connectError;
  final void Function()? onConnected;
  final sent = <String>[];
  var disposed = 0;

  @override
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    await Future<void>.delayed(Duration.zero);
    if (connectError != null) throw connectError!;
    onConnected?.call();
  }

  @override
  Future<bool> send(
    String type, {
    double at = 0,
    Map<String, dynamic>? extra,
  }) async {
    sent.add(type);
    return true;
  }

  @override
  Future<void> dispose() async => disposed++;
}

/// Аудит B-4: экран ушёл, пока ждали комнату, — канал не остаётся висеть.
void main() {
  test('экран жив — подписались, поздоровались, канал открыт', () async {
    final room = _FakeRoom();
    expect(await room.join((_) {}, alive: () => true), isTrue);
    expect(room.sent, ['hello']);
    expect(room.disposed, 0);
  });

  test('экран ушёл во время connect — без hello, канал закрыт', () async {
    var alive = true;
    final room = _FakeRoom(onConnected: () => alive = false);
    expect(await room.join((_) {}, alive: () => alive), isFalse);
    expect(room.sent, isEmpty);
    expect(room.disposed, 1);
  });

  test('connect бросил — канал закрыт, ошибка наружу', () async {
    final room = _FakeRoom(connectError: StateError('нет сети'));
    await expectLater(
      room.join((_) {}, alive: () => true),
      throwsA(isA<StateError>()),
    );
    expect(room.sent, isEmpty);
    expect(room.disposed, 1);
  });
}
