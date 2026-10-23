import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/room_message_time.dart';

void main() {
  test('same day uses time, other days include a date, missing time stays missing', () {
    final now = DateTime(2026, 10, 23, 12);
    String format(DateTime at) => forkRoomMessageTime(at.millisecondsSinceEpoch, now: now);
    expect(format(DateTime(2026, 10, 23, 9, 5)), '09:05');
    expect(format(DateTime(2026, 10, 22, 23, 59)), '22.10 23:59');
    expect(format(DateTime(2025, 10, 22, 23, 59)), '22.10.2025 23:59');
    expect(forkRoomMessageTime(0), isEmpty);
    expect(forkRoomMessageTime(99999999999999999), isEmpty);
  });
}
