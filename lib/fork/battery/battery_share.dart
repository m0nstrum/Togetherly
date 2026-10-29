/// Заряд телефона — партнёру (просьба владельца 22.10, «как в Jagat»).
///
/// Смысл — видеть «у неё 5%», когда она как раз не отвечает. Поэтому заряд
/// хранится записью (`fork_battery`, одна на человека в паре), а не живёт
/// только сигналом «в сети»: партнёр видит последний известный уровень и
/// когда он был. Уровень и «заряжается» лежат в поле `state` шифром ключа
/// пары (record_codec.dart) — сервер видит только, что запись обновилась.
///
/// Пишем редко: при заметной смене уровня (5%), смене «заряжается» или раз в
/// полчаса — и в приложении, и из фоновой задачи WorkManager. Выключается в
/// настройках («Показывать партнёру заряд»), тогда своя запись удаляется.
library;

import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/centrifugo_service.dart';
import '../../services/pocketbase_service.dart';
import '../realtime/subscribed_stream.dart';

@immutable
class ForkBatteryState {
  const ForkBatteryState({
    required this.level,
    required this.charging,
    required this.at,
  });

  final int level;
  final bool charging;
  final DateTime at;

  /// Скоро сядет.
  bool get low => level <= 20 && !charging;

  /// Старше шести часов заряд уже ничего не говорит — не показываем.
  bool fresh(DateTime now, {Duration maxAge = const Duration(hours: 6)}) =>
      now.difference(at) < maxAge;

  Map<String, dynamic> toJson() => {
    'l': level,
    'c': charging,
    'at': at.millisecondsSinceEpoch,
  };

  static ForkBatteryState? fromJson(Object? raw) {
    Object? v = raw;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null; // шифр без ключа или мусор
      }
    }
    if (v is! Map) return null;
    final l = v['l'], at = v['at'];
    if (l is! num || at is! num) return null;
    return ForkBatteryState(
      level: l.toInt().clamp(0, 100),
      charging: v['c'] == true,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }
}

class ForkBattery {
  ForkBattery._();
  static final ForkBattery instance = ForkBattery._();

  static const _shareKey = 'fork_battery_share';
  static const _lastKey = 'fork_battery_last';
  static const String collection = 'fork_battery';

  /// Пишем, если уровень сдвинулся на столько процентов…
  static const int step = 5;

  /// …или прошло столько времени с прошлой записи.
  static const Duration every = Duration(minutes: 30);

  /// Показывать ли партнёру свой заряд (по умолчанию — да).
  final ValueNotifier<bool> sharing = ValueNotifier(true);

  @visibleForTesting
  Future<(int, bool)?> Function() read = _readDevice;

  String _groupId = '';
  String _uid = '';
  Timer? _timer;
  Timer? _partnerSoon;
  int _generation = 0;
  StreamSubscription<BatteryState>? _stateSub;
  bool _loaded = false;

  static Future<(int, bool)?> _readDevice() async {
    try {
      final b = Battery();
      final level = await b.batteryLevel;
      final st = await b.batteryState;
      if (level < 0) return null;
      return (level, st == BatteryState.charging || st == BatteryState.full);
    } catch (e) {
      debugPrint('ForkBattery: заряд не прочитан: $e');
      return null;
    }
  }

  /// Прочитать настройку «показывать заряд» (для переключателя).
  Future<void> ensureLoaded() => _load();

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      sharing.value = p.getBool(_shareKey) ?? true;
    } catch (_) {
      // тихо: без настроек — по умолчанию показываем
    }
  }

  /// Писать ли новую запись вместо прошлой [last].
  static bool shouldSend(ForkBatteryState? last, ForkBatteryState next) {
    if (last == null) return true;
    if (last.charging != next.charging) return true;
    if ((last.level - next.level).abs() >= step) return true;
    return next.at.difference(last.at) >= every;
  }

  /// Пара появилась (или сменилась): следим за зарядом, пока приложение живо.
  ///
  /// [partnerUid] и [onPartner] — заряд партнёра сменился (виджет карты на
  /// рабочем столе перерисовывается сразу, а не через 15 минут фона).
  Future<void> start(
    String groupId,
    String uid, {
    String partnerUid = '',
    VoidCallback? onPartner,
  }) async {
    if (groupId.isEmpty || uid.isEmpty) return;
    if (groupId == _groupId && uid == _uid && _timer != null) return;
    stop();
    final generation = _generation;
    _groupId = groupId;
    _uid = uid;
    if (partnerUid.isNotEmpty && onPartner != null) {
      var first = true;
      _partnerSub = watch(groupId, partnerUid).listen((_) {
        if (first) {
          first = false; // первое — то, что уже было записано
          return;
        }
        _partnerSoon?.cancel();
        _partnerSoon = Timer(const Duration(seconds: 2), onPartner);
      });
    }
    await _load();
    if (generation != _generation) return;
    _timer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(report()),
    );
    try {
      _stateSub = Battery().onBatteryStateChanged.listen(
        (_) => unawaited(report()),
      );
    } catch (e) {
      debugPrint('ForkBattery: без событий зарядки: $e');
    }
    unawaited(report());
  }

  void stop() {
    _generation++;
    _groupId = '';
    _uid = '';
    _partnerSoon?.cancel();
    _partnerSoon = null;
    _timer?.cancel();
    _timer = null;
    unawaited(_stateSub?.cancel());
    _stateSub = null;
    unawaited(_partnerSub?.cancel());
    _partnerSub = null;
  }

  StreamSubscription<ForkBatteryState?>? _partnerSub;

  /// Прочитать заряд и, если пора, записать.
  Future<void> report({
    String? groupId,
    String? uid,
    bool force = false,
  }) async {
    final generation = _generation;
    final g = groupId ?? _groupId, u = uid ?? _uid;
    await _load();
    if (generation != _generation || g.isEmpty || u.isEmpty || !sharing.value)
      return;
    final r = await read();
    if (r == null || generation != _generation) return;
    final next = ForkBatteryState(
      level: r.$1,
      charging: r.$2,
      at: DateTime.now(),
    );
    SharedPreferences? p;
    ForkBatteryState? last;
    try {
      p = await SharedPreferences.getInstance();
      final raw = p.getString('$_lastKey:$g');
      last = raw == null ? null : ForkBatteryState.fromJson(raw);
    } catch (_) {
      // тихо: не знаем прошлого — запишем
    }
    if (generation != _generation || !sharing.value) return;
    if (!force && !shouldSend(last, next)) return;
    if (await _write(g, u, next, generation)) {
      try {
        await p?.setString('$_lastKey:$g', jsonEncode(next.toJson()));
      } catch (_) {
        // тихо: в худшем случае запишем лишний раз
      }
    }
  }

  RecordService get _col => PocketBaseService().pb.collection(collection);

  Future<RecordModel?> _find(String groupId, String uid) async {
    try {
      return await _col.getFirstListItem(
        PocketBaseService().pb.filter('group_id = {:g} && user_uid = {:u}', {
          'g': groupId,
          'u': uid,
        }),
      );
    } on ClientException catch (e) {
      if (e.statusCode != 404) debugPrint('ForkBattery: чтение не вышло: $e');
      return null;
    }
  }

  Future<bool> _write(
    String groupId,
    String uid,
    ForkBatteryState s,
    int generation,
  ) async {
    try {
      final body = {'group_id': groupId, 'user_uid': uid, 'state': s.toJson()};
      final old = await _find(groupId, uid);
      if (generation != _generation || PocketBaseService().userId != uid)
        return false;
      if (old == null) {
        await _col.create(body: body);
      } else {
        await _col.update(old.id, body: body);
      }
      return true;
    } catch (e) {
      // Нет ключа пары — запись не уйдёт открытым текстом (fail-closed).
      debugPrint('ForkBattery: запись не вышла: $e');
      return false;
    }
  }

  /// Переключатель в настройках. Выключили — своя запись пропадает у
  /// партнёра сразу.
  Future<void> setSharing(bool on) async {
    await _load();
    sharing.value = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_shareKey, on);
      if (!on) await p.remove('$_lastKey:$_groupId');
    } catch (_) {
      // тихо: настройка проживёт до перезапуска
    }
    if (_groupId.isEmpty || _uid.isEmpty) return;
    if (on) {
      await report(force: true);
      return;
    }
    final old = await _find(_groupId, _uid);
    if (old == null) return;
    try {
      await _col.delete(old.id);
    } catch (e) {
      debugPrint('ForkBattery: запись не удалена: $e');
    }
  }

  /// Последний записанный заряд [uid] — один раз (виджет карты, фон).
  Future<ForkBatteryState?> latest(String groupId, String uid) async {
    if (groupId.isEmpty || uid.isEmpty) return null;
    final rec = await _find(groupId, uid);
    return rec == null ? null : ForkBatteryState.fromJson(rec.data['state']);
  }

  /// Заряд [uid] в паре [groupId]: сначала последнее записанное, потом живые
  /// изменения по каналу пары.
  Stream<ForkBatteryState?> watch(String groupId, String uid) {
    if (groupId.isEmpty || uid.isEmpty) return Stream.value(null);
    Future<void> fetch(void Function(ForkBatteryState?) add) async {
      final rec = await _find(groupId, uid);
      add(rec == null ? null : ForkBatteryState.fromJson(rec.data['state']));
    }

    // RT-5: уход слушателя до конца подписки не оставляет канал висеть.
    return subscribedStream<ForkBatteryState?>(
      start: (add) => unawaited(fetch(add)),
      subscribe: (add) => CentrifugoService.instance.subscribeDelta(
        'pair:$groupId',
        collection,
        (e) {
          if (e.action == 'delete') {
            add(null);
            return;
          }
          final s = ForkBatteryState.fromJson(e.record?.data['state']);
          if (s != null) {
            add(s);
          } else {
            unawaited(
              fetch(add),
            ); // событие пришло нерасшифрованным — перечитаем
          }
        },
        match: (r) => r.data['user_uid'] == uid,
      ),
    );
  }
}
