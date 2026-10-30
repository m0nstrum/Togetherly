import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D11: геопозиция взаимна. Сервис гонит геолокатор и сеть, поэтому порядок
/// проверяется по исходнику (как `live_location_solo_test.dart`).
void main() {
  final src = File(
    'lib/services/live_location_service.dart',
  ).readAsStringSync();

  String between(String from, String to) {
    final a = src.indexOf(from);
    final b = src.indexOf(to, a + 1);
    expect(a, greaterThanOrEqualTo(0), reason: 'нет $from');
    expect(b, greaterThan(a), reason: 'нет $to');
    return src.substring(a, b);
  }

  test('точки партнёра и своя — только через гейт взаимности', () {
    expect(
      between(
        'Stream<LivePoint?> watchPartner(',
        'Stream<LivePoint?> watchSelf(',
      ),
      contains('whileMutual'),
    );
    expect(
      between(
        'Stream<LivePoint?> watchSelf(',
        'Stream<LivePoint?> _watchPoint(',
      ),
      contains('whileMutual'),
    );
  });

  test('выключение прячет партнёра до сети и чистит виджет', () {
    final off = between(
      '    } else {\n      // fork (D11)',
      '  Future<void> _persist(',
    );
    expect(
      off.indexOf('mutualChannel.value = null'),
      lessThan(off.indexOf('await')),
      reason: 'точка партнёра обязана исчезнуть до первого сетевого шага',
    );
    expect(off, contains('_forgetPartnerOnWidget'));
  });

  test('сигнал остановки уходит до удаления своей записи', () {
    final stop = between(
      'Future<void> stopSharing(',
      '// fork (UX G2): партнёр держит',
    );
    expect(
      stop.indexOf('_announceStop'),
      lessThan(stop.indexOf('clearLivePoint')),
      reason: 'без записи сервер уже не пустит в канал',
    );
  });

  test('флаг «делюсь» на сервере заводится до подъёма потока', () {
    final start = between('Future<void> startSharing(', 'void _onStreamError(');
    expect(start, contains('ensureLiveMarker'));
    expect(
      start.indexOf('ensureLiveMarker'),
      lessThan(start.indexOf('_canStartFgs')),
    );
  });

  test('удачная запись точки открывает гейт, если флаг не подтвердился', () {
    final push = between('Future<void> _push(', 'Timer? _storeTimer;');
    expect(push, contains('_confirmMutual'));
    final flush = between(
      'Future<void> _flushUnstored(',
      'Future<void> _cancelStream(',
    );
    expect(flush, contains('_confirmMutual'));
  });
}
