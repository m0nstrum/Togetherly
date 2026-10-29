import 'dart:async';
import 'dart:math';

/// Открытый список дотягивает с сервера то, что прошло мимо сокета (TOG-17).
///
/// О новых сообщениях чат узнаёт из сокета Centrifugo, а сокет рвётся всё
/// время: мобильная сеть, сон телефона, MIUI. События, случившиеся в разрыв,
/// не досылаются никогда, и сообщение партнёра появлялось только после выхода
/// из чата и повторного входа («при входе в чат их некоторое время не видно»,
/// отзыв в Google Play, 1.38.0).
///
/// Поводов дотянуть три:
///  * сокет переподключился — с разбросом [jitter], чтобы после перезапуска
///    сервера все открытые чаты не пришли за списком одной секундой;
///  * приложение вернулось на экран после паузы дольше [minAway];
///  * сокета нет, а список открыт и приложение на экране — раз в [pollEvery],
///    пока сокета нет (`null` — без опроса);
///  * прочие поводы [nudges] — например, вернулся ключ подписи сервера, без
///    которого дельты канала отбрасывались (RT-3); с тем же разбросом.
///
/// Догоны не идут вперехлёст: повод, случившийся во время догона, даёт ещё
/// один догон после него — сообщение могло прийти, пока шёл запрос.
///
/// Шторм поводов (сокет моргает каждую секунду) не превращается в шторм
/// запросов (RT-2): отложенный догон один на всех, а новый начинается не
/// раньше чем через [minInterval] после начала прошлого — повод, пришедший
/// раньше, переносится на конец этого окна, а не теряется.
class CatchUpDriver {
  CatchUpDriver({
    required Future<void> Function() catchUp,
    required Stream<void> reconnected,
    required Stream<bool> foreground,
    required bool Function() subscribed,
    Stream<void>? nudges,
    Duration? pollEvery = const Duration(seconds: 15),
    Duration minAway = const Duration(seconds: 3),
    Duration minInterval = Duration.zero,
    Duration Function()? jitter,
    DateTime Function()? now,
  }) : _catchUp = catchUp,
       _subscribed = subscribed,
       _minAway = minAway,
       _minInterval = minInterval,
       _jitter = jitter ?? _randomJitter,
       _now = now ?? DateTime.now {
    _subs.add(reconnected.listen((_) => _schedule(_jitter())));
    if (nudges != null) {
      _subs.add(nudges.listen((_) => _schedule(_jitter())));
    }
    _subs.add(foreground.listen(_onForeground));
    if (pollEvery != null) {
      _poll = Timer.periodic(pollEvery, (_) {
        if (_inForeground && !_subscribed()) _request();
      });
    }
  }

  final Future<void> Function() _catchUp;
  final bool Function() _subscribed;
  final Duration _minAway;
  final Duration _minInterval;
  final Duration Function() _jitter;
  final DateTime Function() _now;

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _delayed;
  Timer? _poll;
  bool _inForeground = true;
  DateTime? _awayAt;
  DateTime? _lastStart;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  static final Random _rnd = Random();
  static Duration _randomJitter() =>
      Duration(milliseconds: 300 + _rnd.nextInt(1200));

  void _onForeground(bool visible) {
    if (!visible) {
      _inForeground = false;
      _awayAt ??= _now();
      return;
    }
    _inForeground = true;
    final away = _awayAt;
    _awayAt = null;
    if (away != null && _now().difference(away) >= _minAway) _request();
  }

  void _schedule(Duration delay) {
    if (_disposed) return;
    if (delay <= Duration.zero) {
      _request();
      return;
    }
    // Отложенный догон уже ждёт: он начнётся после этого повода и покроет его.
    if (_delayed != null) return;
    _delayed = Timer(delay, () {
      _delayed = null;
      _request();
    });
  }

  void _request() {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    final last = _lastStart;
    if (last != null) {
      final wait = _minInterval - _now().difference(last);
      if (wait > Duration.zero) {
        _schedule(wait);
        return;
      }
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    _again = false;
    _lastStart = _now();
    try {
      await _catchUp();
    } catch (_) {
      // тихо: сеть или сервер не ответили — следующий повод попробует снова.
    } finally {
      _running = false;
    }
    // Повод пришёл во время догона — ещё один, но через [_request]: так и он
    // не чаще [_minInterval].
    if (_again && !_disposed) {
      _again = false;
      _request();
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    _delayed?.cancel();
    _delayed = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }
}
