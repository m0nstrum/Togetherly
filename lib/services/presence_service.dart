import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';
import '../models/presence_liveness.dart';
import '../models/presence_tracker.dart';
import '../fork/e2e/fork_e2e.dart';
import 'centrifugo_service.dart';
import 'pocketbase_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';

/// «Мы оба тут» — через канал пары, а не через диск.
///
/// Как было до 14 августа 2026: каждый телефон обновлял `user_presence.seen_at`
/// раз в двенадцать секунд. При семистах активных это под шестьдесят записей в
/// секунду, а писатель у SQLite один — сохранение статуса, сообщения и
/// настроения вставали в очередь за чужими «я ещё тут». В ту ночь сервер на
/// этом и захлебнулся: запись висела по тридцать секунд, люди видели «сервер не
/// отвечает» и не могли войти.
///
/// Как стало: «я жив» летит публикацией в канал `pair:<группа>` и на диск не
/// попадает вовсе. В базу уходит редкая отметка раз в пять минут — только ради
/// подписи «была в 12:33» в шапке чата.
///
/// Партнёр со сборкой постарше про канал не знает и по-прежнему пишет отметки в
/// базу. Поэтому онлайн считается по двум источникам сразу: берём тот, что
/// свежее. Пока такие сборки живы, ничего не теряется.
///
/// B10 (29.10.2026, «партнёр офлайн, хотя пишет»): жив тот, от кого хоть что-то
/// пришло — удар, «печатает», касание, реплика чата; свежесть — по времени
/// приёма, а не по часам партнёра; подписка встала (и после обрыва) — удар с
/// просьбой ответить; свернул приложение — «ушёл» сразу. Подробности —
/// [PresenceTracker].
class PresenceService with WidgetsBindingObserver {
  PresenceService._(this._wire, this._tracker);
  static final PresenceService instance = PresenceService._(
    _LiveWire(),
    PresenceTracker(),
  );
  factory PresenceService() => instance;

  /// Отдельный экземпляр для тестов: свой канал и свои часы.
  @visibleForTesting
  PresenceService.test(PresenceWire wire, {int Function()? nowMs})
    : _wire = wire,
      _tracker = PresenceTracker(nowMs: nowMs);

  final PresenceWire _wire;
  final PresenceTracker _tracker;

  Timer? _heartbeat;
  bool _started = false;
  bool _away = false;
  int _generation = 0; // fork: M7 cancel pending subscriptions
  String _groupId = '';
  int? _lastStoredMs;

  /// Кому рассказать, что признак жизни обновился.
  final StreamController<String> _pulse = StreamController<String>.broadcast();

  final List<RtUnsub> _unsubs = <RtUnsub>[];
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];

  String get _uid => _wire.me;

  String _channel(String groupId) => 'pair:$groupId';

  bool _live(int generation) => _started && generation == _generation;

  /// Запустить (после входа и появления пары). Идемпотентно.
  ///
  /// Без [groupId] сервис работает по-старому — через отметки в базе: у
  /// одиночки канала пары нет.
  void start({String groupId = ''}) {
    if (_started && groupId == _groupId) return;
    if (_started) stop();
    _started = true;
    _away = false;
    _groupId = groupId;
    _wire.observe(this, true);
    if (groupId.isNotEmpty) unawaited(_listenChannel(groupId));
    // Первый удар просит ответа: партнёр, который уже здесь, отзовётся сразу,
    // а не через двадцать секунд.
    _beat(ask: true);
    _heartbeat = Timer.periodic(PresenceLiveness.beat, (_) => _beat());
  }

  void stop() {
    final wasStarted = _started;
    _started = false;
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    for (final u in _unsubs) {
      unawaited(u().catchError((Object _) {})); // тихо: канал уже закрыт
    }
    _unsubs.clear();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _tracker.clear();
    _lastStoredMs = null;
    _groupId = '';
    if (wasStarted) _wire.observe(this, false);
  }

  /// Партнёр [uid] подал признак жизни мимо канала пары (экран, который сам
  /// проверил его подпись). Ответим ударом, если до этого он был не в сети.
  void noteActivity(String uid) {
    if (!_started || uid.isEmpty || uid == _uid) return;
    _heard(uid);
  }

  void _heard(String uid, {bool ask = false}) {
    final fresh = _tracker.heard(uid);
    _notify(uid);
    if ((fresh || ask) && _tracker.shouldAnswer()) _beat();
  }

  void _notify(String uid) {
    if (!_pulse.isClosed) _pulse.add(uid);
  }

  Future<void> _listenChannel(String groupId) async {
    final generation = _generation;
    final channel = _channel(groupId);
    void keep(RtUnsub unsub) {
      if (_live(generation)) {
        _unsubs.add(unsub);
      } else {
        unawaited(unsub().catchError((Object _) {})); // тихо: уже остановлены
      }
    }

    keep(
      await _wire.listen(channel, (raw) {
        if (!_live(generation)) return;
        // fork (E2E): сигнал — шифром ключа пары. Не открылся (ключ ещё не
        // доехал) — его отправителя всё равно учтёт [PresenceWire.publishers].
        final data = _wire.open(channel, raw);
        if (data == null) return;
        final uid = (data['uid'] ?? '').toString();
        if (uid.isEmpty || uid == _uid) return;
        if (data['t'] == 'away') {
          _tracker.gone(uid);
          _notify(uid);
          return;
        }
        // Любой сигнал партнёра — alive, typing и прочее — значит «жив».
        _heard(uid, ask: data['ask'] == true);
      }),
    );
    if (!_live(generation)) return;
    // Отправителя публикации называет сервер: так жив и тот, чей пакет не
    // открылся, и экран «Прикосновение», и сборки с новыми сигналами.
    _subs.add(
      _wire.publishers(channel).listen((who) {
        if (_live(generation) && who.isNotEmpty && who != _uid) _heard(who);
      }),
    );
    // Подписка встала — первый раз или после обрыва связи: события разрыва
    // пропали, поэтому здороваемся заново и просим ответа.
    _subs.add(
      _wire.subscribed(channel).listen((_) {
        if (_live(generation) && !_away) _beat(ask: true);
      }),
    );
    // Реплика партнёра — тоже признак жизни, даже если «печатает» не дошло.
    keep(
      await _wire.chat(channel, (event) {
        if (!_live(generation) || event.action != 'create') return;
        final uid = (event.record?.data['user_uid'] ?? '').toString();
        if (uid.isNotEmpty && uid != _uid) _heard(uid);
      }),
    );
  }

  void _beat({bool ask = false}) {
    if (!_started) return;
    final uid = _uid;
    if (uid.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_groupId.isNotEmpty) {
      // Публикация не касается диска: её видит только тот, кто сейчас в канале.
      _wire.signal(_groupId, _channel(_groupId), {
        't': 'alive',
        'uid': uid,
        'at': now,
        if (ask) 'ask': true,
      });
    }

    // Отметка «был в сети» нужна для подписи в шапке чата, и только для неё.
    if (PresenceLiveness.shouldWriteLastSeen(
      writtenAtMs: _lastStoredMs,
      nowMs: now,
    )) {
      _lastStoredMs = now;
      _wire.store(uid);
    }
  }

  /// «Ушёл»: партнёр видит офлайн сразу, а не после сорока пяти секунд
  /// тишины. Сборки постарше тип `away` не знают и просто его пропускают.
  void _goAway() {
    if (_away || _groupId.isEmpty || _uid.isEmpty) return;
    _away = true;
    _wire.signal(_groupId, _channel(_groupId), {
      't': 'away',
      'uid': _uid,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _away = false;
        _beat(ask: true);
        _heartbeat ??= Timer.periodic(PresenceLiveness.beat, (_) => _beat());
      case AppLifecycleState.inactive:
        // Шторка, системный диалог, картинка-в-картинке: человек тут же, у
        // экрана. Раньше и это гасило удары, и партнёр с видео в окошке через
        // сорок пять секунд выглядел офлайн.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _heartbeat?.cancel();
        _heartbeat = null;
        _goAway();
    }
  }

  /// Когда [uid] в последний раз был в сети — миллисекунды эпохи.
  ///
  /// Шапке чата нужен сам момент («была в 12:33»), поэтому смотрим и удары по
  /// каналу, и отметку в базе.
  Stream<int?> watchLastSeen(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _merged(uid).map((v) => v.$2);
  }

  /// В сети ли [uid] — живой поток.
  Stream<bool> watchOnline(String uid) {
    if (uid.isEmpty) return Stream.value(false);
    return _merged(uid).map((v) => v.$1).distinct();
  }

  /// Общий поток: (в сети, когда видели). Собирает канал, базу и часы.
  Stream<(bool, int?)> _merged(String uid) {
    late StreamController<(bool, int?)> ctrl;
    StreamSubscription<int?>? dbSub;
    StreamSubscription<String>? pulseSub;
    Timer? ticker;
    int? storedMs;

    void emit() {
      final online = _tracker.online(uid, storedSeenMs: storedMs);
      final seen = _tracker.lastSeen(uid, storedSeenMs: storedMs);
      if (!ctrl.isClosed) ctrl.add((online, seen));
    }

    ctrl = StreamController<(bool, int?)>(
      onListen: () {
        // База: отметка партнёра приезжает редко, но она же держит совместимость
        // со сборками, которые про канал ещё не знают.
        dbSub = _wire.stored(uid).listen((ms) {
          storedMs = ms;
          emit();
        }, onError: (_) {});
        pulseSub = _pulse.stream.where((u) => u == uid).listen((_) => emit());
        // Часы: без них точка не погаснет, когда удары просто прекратились.
        ticker = Timer.periodic(const Duration(seconds: 10), (_) => emit());
        emit();
      },
      onCancel: () {
        dbSub?.cancel();
        pulseSub?.cancel();
        ticker?.cancel();
      },
    );
    return ctrl.stream;
  }
}

/// Всё, чем присутствие говорит с миром: канал пары, шифр, база, жизненный
/// цикл. В приложении — [_LiveWire], в тестах — заглушка.
abstract class PresenceWire {
  String get me;

  /// Сырые публикации канала пары.
  Future<RtUnsub> listen(
    String channel,
    void Function(Map<String, dynamic>) onData,
  );

  /// Отправители публикаций канала (uid по данным сервера).
  Stream<String> publishers(String channel);

  /// Подписка на канал встала (в том числе после переподключения).
  Stream<void> subscribed(String channel);

  /// Дельты чата пары.
  Future<RtUnsub> chat(String channel, void Function(RtEvent) onEvent);

  /// Открыть сигнал; подделка или нечем открыть — null.
  Map<String, dynamic>? open(String channel, Map<String, dynamic> raw);

  /// Запечатать и отправить сигнал; нет ключа пары — не отправляем.
  void signal(String groupId, String channel, Map<String, dynamic> msg);

  /// Отметка «был в сети» в базе: своя — записать, чужая — слушать.
  void store(String uid);
  Stream<int?> stored(String uid);

  void observe(WidgetsBindingObserver o, bool on);
}

class _LiveWire implements PresenceWire {
  @override
  String get me => PocketBaseService().userId ?? '';

  @override
  Future<RtUnsub> listen(
    String channel,
    void Function(Map<String, dynamic>) onData,
  ) => CentrifugoService().subscribeRaw(channel, onData);

  @override
  Stream<String> publishers(String channel) =>
      CentrifugoService().publishers(channel);

  @override
  Stream<void> subscribed(String channel) =>
      CentrifugoService().subscribedTo(channel);

  @override
  Future<RtUnsub> chat(String channel, void Function(RtEvent) onEvent) =>
      CentrifugoService().subscribeDelta(channel, 'chat_messages', onEvent);

  @override
  Map<String, dynamic>? open(String channel, Map<String, dynamic> raw) =>
      ForkE2E.openSignal(channel, raw);

  @override
  void signal(String groupId, String channel, Map<String, dynamic> msg) {
    // fork (E2E): сигнал шифром ключа пары; нет ключа — не шлём.
    final sealed = ForkE2E.sealSignal(groupId, channel, msg);
    if (sealed != null) unawaited(CentrifugoService().publish(channel, sealed));
  }

  @override
  void store(String uid) => unawaited(PbDataService().touchPresence(uid));

  @override
  Stream<int?> stored(String uid) => PbRealtimeService()
      .watchPresence(uid)
      .map((RecordModel? rec) => (rec?.data['seen_at'] as num?)?.toInt());

  @override
  void observe(WidgetsBindingObserver o, bool on) => on
      ? WidgetsBinding.instance.addObserver(o)
      : WidgetsBinding.instance.removeObserver(o);
}
