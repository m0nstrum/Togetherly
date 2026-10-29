// RT-2: каждая живая область стоит под догоном SyncCoordinator.
//
// Само правило — в sync_coordinator_test.dart и catch_up_driver_test.dart.
// Здесь — что области его включают: без регистрации поток снова видит только
// сокет, и изменение партнёра, случившееся в разрыв, ждёт смены сети. Поломка
// тихая, ни одной ошибки в журнале.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _body(String src, String start, String end) {
  final from = src.indexOf(start);
  expect(from, isNonNegative, reason: '$start не найден');
  final to = src.indexOf(end, from + start.length);
  expect(to, isNonNegative, reason: '$end после $start не найден');
  return src.substring(from, to);
}

void main() {
  final src = File('lib/services/pb_realtime_service.dart').readAsStringSync();

  test('кэш-списки, документы и in-memory-списки регистрируют догон', () {
    for (final (start, end) in [
      ('Stream<List<RecordModel>> watchList(', 'Stream<RecordModel?> watchRecord('),
      ('Stream<RecordModel?> watchRecord(', 'Stream<List<RecordModel>> _watchCached('),
      ('Stream<List<RecordModel>> _watchCached(', 'Stream<RecordModel?> _watchRecordCached('),
      ('Stream<RecordModel?> _watchRecordCached(', 'Stream<RecordModel?> watchGroup('),
    ]) {
      final body = _body(src, start, end);
      expect(
        body,
        contains('SyncCoordinator.instance.register('),
        reason: '$start без догона',
      );
      expect(body, contains('catchUp?.dispose()'), reason: '$start: утечка');
    }
  });

  test('чат, пока сокета нет, дотягивает по таймеру', () {
    final body = _body(
      src,
      'Stream<List<RecordModel>> watchMessages(',
      ');',
    );
    expect(body, contains('pollWithoutSocket: true'));
  });

  test('кэш-список при догоне сверяет состав, если сверка включена', () {
    final body = _body(
      src,
      'Stream<List<RecordModel>> _watchCached(',
      'Stream<RecordModel?> _watchRecordCached(',
    );
    expect(body, contains('if (reconcile && !cancelled) await reconcileOnce()'));
  });

  test('подарки на главном экране догоняются', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    final body = _body(home, 'Future<void> _listenGifts() async {', '\n  }\n');
    expect(body, contains('SyncCoordinator.instance.register('));
    expect(home, contains('_giftsCatchUp?.dispose()'));
  });

  test('координатор слушает переподключение, возврат и ключ подписи', () {
    final c = File('lib/services/sync_coordinator.dart').readAsStringSync();
    expect(c, contains('reconnected: CentrifugoService.instance.reconnected'));
    expect(c, contains('onShow: () => visible.add(true)'));
    expect(c, contains('keyRecovered: ForkVerifiedDelta.keyRecovered'));
  });
}
