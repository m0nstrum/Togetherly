import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fgs_start_allowed.dart';
import '../models/live_location_tuning.dart';
import '../models/map_distance.dart';
import 'locale_service.dart';
import 'centrifugo_service.dart';
import 'map/pair_map_widget_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';
import 'pocketbase_service.dart';
import '../fork/e2e/fork_e2e.dart';
import '../fork/realtime/subscribed_stream.dart';
import '../fork/location_consent.dart';
import '../fork/geo/geo_status.dart';
import '../fork/geo/mutual_location.dart';
import '../fork/wishes/wish_places.dart';

/// Флаг «показ включён» в SharedPreferences. Его же читает виджет «Где мы»
/// в фоне (D11: сам не делишься — партнёра на виджете нет).
const String kLiveSharingEnabledKey = 'live_location_sharing_enabled';

/// Снимок позиции участника пары. Живёт в PocketBase (коллекция `live_location`,
/// json `data` в канале пары) и НЕ удаляется на disconnect — поэтому последняя
/// точка партнёра видна на карте даже когда он офлайн.
@immutable
class LivePoint {
  final double lat;
  final double lng;
  final double accuracy; // метры
  final double? heading; // градусы (может отсутствовать)
  final int updatedAt; // epoch ms (клиентское время записи точки)

  const LivePoint({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.updatedAt,
    this.heading,
  });

  LatLng get latLng => LatLng(lat, lng);

  factory LivePoint.fromMap(Map<dynamic, dynamic> m) {
    return LivePoint(
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
      heading: (m['heading'] as num?)?.toDouble(),
      updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Сервис live-локации пары. Транспорт — PocketBase (миграция §3, коллекция
/// `live_location`): свою позицию пишем стримом геолокатора (фоновый
/// foreground-service на Android, background updates на iOS), позицию партнёра —
/// слушаем live-подпиской PB.
class LiveLocationService with WidgetsBindingObserver {
  LiveLocationService._();
  static final LiveLocationService instance = LiveLocationService._();

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  String get _uid => PocketBaseService().userId ?? '';

  /// Общий для ОБОИХ партнёров узел live-локации: детерминированный ключ из
  /// пары uid, отсортированных лексикографически. В отличие от pairId он НЕ
  /// зависит от того, какой из (возможно дублирующихся) групповых документов
  /// сейчас активен на конкретном телефоне — оба партнёра всегда вычисляют
  /// один и тот же узел и потому видят друг друга. Фолбэк на pairId, если
  /// партнёр неизвестен (например, группа из 3+ участников).
  String _channel(String pairId, String partnerUid) {
    if (_uid.isEmpty || partnerUid.isEmpty) return pairId;
    final ids = [_uid, partnerUid]..sort();
    return 'pair_${ids[0]}_${ids[1]}';
  }

  StreamSubscription<Position>? _posSub;
  String? _activePairId;
  int _sessionGeneration = 0; // fork: M7 stale async work

  /// С каким профилем сейчас крутится поток. По нему видно, что пора
  /// перезапуститься: экономный профиль в фоне и точный на экране.
  bool? _streamForeground;
  bool _observing = false;

  /// Включён ли шеринг (персистентно, между запусками). UI слушает этот флаг.
  final ValueNotifier<bool> sharingEnabled = ValueNotifier<bool>(false);

  /// fork (D11): канал, где сервер уже знает «я делюсь» — там лежит своя
  /// запись. Точку партнёра сервер отдаёт только в таком канале, поэтому и
  /// клиент без него на неё не подписывается. null — не делимся нигде.
  final ValueNotifier<String?> mutualChannel = ValueNotifier<String?>(null);

  late final Listenable _mutualGate = Listenable.merge([
    sharingEnabled,
    mutualChannel,
  ]);

  /// fork (D11): видно ли сейчас партнёра — только когда делишься сам.
  bool canSeePartner(String pairId, String partnerUid) =>
      _mutualOpen(_channel(pairId, partnerUid));

  bool _mutualOpen(String channel) =>
      sharingEnabled.value && mutualChannel.value == channel;

  /// true, пока крутится стрим позиции.
  bool get isSharing => _posSub != null;

  /// Последняя своя точка из потока показа. Её берёт экран большой карты:
  /// своя подписка на общий нативный поток держала бы его после «Выключить»
  /// (см. `MyPositionFeed`, обращение 383).
  final ValueNotifier<Position?> myFix = ValueNotifier<Position?>(null);

  /// fork (UX G3/G4): почему включённый показ на самом деле не передаёт.
  final ValueNotifier<ShareIssue> issue = ValueNotifier<ShareIssue>(
    ShareIssue.none,
  );

  /// fork (UX G13): на iPhone выдали только «При использовании» — закрытое
  /// приложение партнёра не увидит. Человеку об этом говорит карточка.
  final ValueNotifier<bool> backgroundLimited = ValueNotifier<bool>(false);

  /// Загружает сохранённое состояние флага. Вызывать на старте приложения.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sharingEnabled.value = prefs.getBool(kLiveSharingEnabledKey) ?? false;
    } catch (_) {}
  }

  // ── Разрешения ──────────────────────────────────────────────────────────

  /// Запрашивает разрешение на геолокацию. Возвращает true, если выдан хотя бы
  /// whileInUse. На Android при уже выданном whileInUse повторный запрос
  /// предлагает «разрешить всегда» (фон), что нужно для трекинга в фоне.
  Future<bool> ensurePermission() async {
    try {
      // fork (UX G4): выключенная геолокация телефона — отдельная причина,
      // у неё свой экран настроек.
      if (!await Geolocator.isLocationServiceEnabled()) {
        issue.value = ShareIssue.servicesOff;
        return false;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        issue.value = ShareIssue.deniedForever;
        return false;
      }
      if (perm == LocationPermission.denied) {
        issue.value = ShareIssue.denied;
        return false;
      }
      // fork: ACCESS_BACKGROUND_LOCATION объявлен (см. манифест). Без «Всегда»
      // показ живёт на foreground-сервисе, и часть прошивок его душит —
      // карточка предложит «Разрешать всегда» ([requestAlways]).
      backgroundLimited.value =
          Platform.isAndroid && perm == LocationPermission.whileInUse;
      // На iPhone geolocator «Всегда» не спрашивает вовсе — только свой канал.
      if (Platform.isIOS && perm == LocationPermission.whileInUse) {
        final always = await requestAlwaysIOS();
        // fork (UX G13): итог не терялся молча — карточка скажет, что без
        // «Всегда» закрытое приложение партнёра не увидит.
        backgroundLimited.value = always == 'whenInUse' || always == 'denied';
      }
      issue.value = ShareIssue.none;
      return true;
    } catch (e) {
      debugPrint('LiveLocationService.ensurePermission failed: $e');
      issue.value = ShareIssue.denied;
      return false;
    }
  }

  /// fork: попросить «Разрешать всегда». На Android 11+ система открывает
  /// страницу разрешения геопозиции приложения, где этот пункт теперь есть;
  /// на iPhone — свой канал. true — выдано.
  Future<bool> requestAlways() async {
    try {
      if (Platform.isIOS) {
        final r = await requestAlwaysIOS();
        backgroundLimited.value = r != 'always';
        return r == 'always';
      }
      final perm = await Geolocator.requestPermission();
      final ok = perm == LocationPermission.always;
      backgroundLimited.value = !ok && perm == LocationPermission.whileInUse;
      return ok;
    } catch (e) {
      debugPrint('LiveLocationService.requestAlways failed: $e');
      return false;
    }
  }

  /// Канал разрешения «Всегда» (`AppDelegate.setupLocationAlwaysChannel`).
  static const MethodChannel _alwaysChannel = MethodChannel(
    'love_app/location_always',
  );

  /// Просит на iPhone «Разрешить всегда».
  ///
  /// `Geolocator.requestPermission()` на iOS зовёт только
  /// `requestWhenInUseAuthorization`, поэтому фон жил ровно столько, сколько
  /// жил процесс: человек убил приложение — метка партнёра стоит до следующего
  /// открытия. Диалог показывается поверх уже выданного «При использовании» и
  /// ровно один раз: система на повторный запрос ничего не рисует, поэтому
  /// отказ здесь не ошибка — шеринг работает и без «Всегда», просто без
  /// пробуждения закрытого приложения.
  ///
  /// Возвращает состояние словом: `always`, `whenInUse`, `denied`,
  /// `notDetermined`, `unknown`.
  Future<String> requestAlwaysIOS() async {
    if (!Platform.isIOS) return 'unknown';
    try {
      return await _alwaysChannel.invokeMethod<String>('request') ?? 'unknown';
    } on MissingPluginException {
      // Нативной части нет — так бывает у сборок до 1.29.6.
      return 'unknown';
    } catch (e) {
      debugPrint('LiveLocationService: «Всегда» не запросилось: $e');
      return 'unknown';
    }
  }

  // ── Включение/выключение шеринга ──────────────────────────────────────────

  /// Переключает шеринг и сохраняет выбор. При включении запрашивает
  /// разрешение и стартует стрим; при выключении — гасит стрим и удаляет
  /// свою точку из RTDB. Возвращает фактическое состояние (false при отказе
  /// в разрешении).
  Future<bool> setSharingEnabled(
    bool enabled, {
    required String pairId,
    String partnerUid = '',
  }) async {
    if (enabled) {
      final granted = await ensurePermission();
      if (!granted) {
        await _persist(false); // причина — в [issue]
        return false;
      }
      await _persist(true);
      await LocationConsent.remember(
        _uid,
        partnerUid,
      ); // fork: согласие — этому партнёру (UX G1)
      await startSharing(pairId, partnerUid: partnerUid);
      return true;
    } else {
      // fork (D11): точка партнёра прячется сразу, ещё до сети.
      mutualChannel.value = null;
      await _persist(false);
      issue.value = ShareIssue.none; // fork (UX G3)
      backgroundLimited.value = false;
      await LocationConsent.remember(_uid, '');
      final wasActive = _activePairId; // fork (UX G2)
      await stopSharing(removePoint: true);
      // fork (UX G2): стрим мог и не стартовать (фон, нет партнёра) — точку
      // прошлого запуска всё равно убираем.
      final channel = _channel(pairId, partnerUid);
      if (wasActive == null &&
          pairId.isNotEmpty &&
          partnerUid.isNotEmpty &&
          _uid.isNotEmpty) {
        // fork (D11): сигнал — пока своя запись жива: без неё сервер уже не
        // пустит в канал.
        await _announceStop(channel);
        await _data.clearLivePoint(channel, _uid);
        await CentrifugoService().release('loc:$channel');
      }
      _forgetPartnerOnWidget(pairId, partnerUid);
      return false;
    }
  }

  /// fork (D11): на виджете «Где мы» партнёра больше нет — перерисовать без
  /// него и забыть районы, по которым видно, где он был.
  void _forgetPartnerOnWidget(String pairId, String partnerUid) {
    if (pairId.isEmpty || partnerUid.isEmpty || _uid.isEmpty) return;
    unawaited(
      PairMapWidgetService.instance.forgetPartner(
        groupId: pairId,
        myUid: _uid,
        partnerUid: partnerUid,
      ),
    );
  }

  Future<void> _persist(bool v) async {
    sharingEnabled.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kLiveSharingEnabledKey, v);
    } catch (_) {}
  }

  /// Запускает стрим позиции и пишет её в RTDB. Идемпотентно для того же
  /// pairId. Не делает ничего, если шеринг выключен флагом.
  Future<void> startSharing(String pairId, {String partnerUid = ''}) async {
    final generation = _sessionGeneration;
    if (pairId.isEmpty || _uid.isEmpty) return;
    if (!sharingEnabled.value) return;
    // Без партнёра геопозицию не берём вовсе. Читать её всё равно некому:
    // watchPartner на пустом partnerUid отдаёт пустой поток, — а вот писать
    // мы её продолжали, и приложение жгло батарею и держало синюю стрелку у
    // одиночек и у пар с пустым местом («ждём человека»). Ровно на этом стоит
    // претензия App Review 2.5.4: режим `location` объявлен, а функции, ради
    // которой он нужен, у такого человека на экране нет.
    if (partnerUid.isEmpty) {
      await stopSharing(removePoint: true);
      issue.value = ShareIssue.noPartner; // fork (UX G3)
      debugPrint('LiveLocationService: партнёра нет, шеринг не запускаем');
      return;
    }
    // fork: согласие давалось другому партнёру или под другим входом (UX G1).
    final consent = await LocationConsent.allows(_uid, partnerUid);
    if (generation != _sessionGeneration || _uid.isEmpty) return;
    if (!consent) {
      await _persist(false);
      await stopSharing(removePoint: true);
      issue.value = ShareIssue.noConsent; // fork (UX G3)
      debugPrint(
        'LiveLocationService: согласие было не этому партнёру — выключено',
      );
      return;
    }
    final channel = _channel(pairId, partnerUid);
    // fork (D11): своя запись в канале — для сервера флаг «делюсь»; без неё
    // он не отдаёт ни точку партнёра, ни подписку на его канал. Заводим её
    // сразу, не дожидаясь первого фикса.
    if (mutualChannel.value != channel) {
      final marked = await _data.ensureLiveMarker(channel, _uid);
      if (generation != _sessionGeneration || _uid.isEmpty) return;
      if (!sharingEnabled.value) {
        // Выключили, пока запись создавалась: не оставляем флаг на сервере.
        if (marked) await _data.clearLivePoint(channel, _uid);
        return;
      }
      if (marked) mutualChannel.value = channel;
    }
    // Android 12+ запрещает старт foreground-сервиса из фона, а geolocator
    // поднимает location-FGS внутри getPositionStream → из фона это роняет
    // ForegroundServiceStartNotAllowedException (летит мимо try/catch и onError).
    // Поднимаем стрим только на переднем плане; из фона выходим — подхватит
    // resumeIfEnabled при следующем открытии приложения.
    if (generation != _sessionGeneration || _uid.isEmpty) return;
    if (!_canStartFgs()) {
      issue.value = ShareIssue.needsForeground; // fork (UX G3)
      debugPrint('LiveLocationService: старт из фона пропущен (FGS запрещён)');
      return;
    }
    if (_activePairId == channel && _posSub != null) return;

    // Сменился канал — гасим прежний стрим, точку прежнего канала оставляем.
    await _cancelStream();
    if (generation != _sessionGeneration || _uid.isEmpty) return;
    _activePairId = channel;

    // Немедленный первый фикс, чтобы партнёр сразу увидел точку.
    unawaited(_pushCurrent(channel));

    _watchLifecycle();
    _streamForeground = _appInForeground();
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen((pos) => _push(channel, pos), onError: _onStreamError);
      if (issue.value == ShareIssue.needsForeground ||
          issue.value == ShareIssue.noPartner) {
        issue.value = ShareIssue.none; // fork (UX G3)
      }
    } catch (e) {
      debugPrint('LiveLocationService.startSharing failed: $e');
      issue.value = ShareIssue.streamFailed; // fork (UX G3)
    }
  }

  // fork (UX G3): поток сломался уже в работе — система отозвала доступ или
  // выключили геолокацию. Раньше человек видел «включено» при мёртвой передаче.
  void _onStreamError(Object e) {
    debugPrint('live location stream error: $e');
    if (e is PermissionDeniedException) {
      issue.value = ShareIssue.deniedForever;
    } else if (e is LocationServiceDisabledException) {
      issue.value = ShareIssue.servicesOff;
    } else {
      issue.value = ShareIssue.streamFailed;
    }
  }

  /// Подхватывает шеринг на старте приложения / при привязке к группе, если
  /// пользователь его раньше включал. Безопасно вызывать многократно.
  Future<void> resumeIfEnabled(String pairId, {String partnerUid = ''}) async {
    if (!sharingEnabled.value) return;
    // Партнёр мог уйти, пока приложение было закрыто: пара распалась или
    // второе место ещё пустует. Тогда не просто не стартуем, а гасим то, что
    // осталось с прошлого запуска.
    if (partnerUid.isEmpty) {
      await stopSharing(removePoint: true);
      issue.value = ShareIssue.noPartner; // fork (UX G3)
      return;
    }
    await startSharing(pairId, partnerUid: partnerUid);
  }

  void _watchLifecycle() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Ушли с экрана — перезапускаем поток экономным профилем, вернулись —
  /// точным. Настройки `getPositionStream` на лету не меняются, поэтому
  /// именно перезапуск.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // fork (UX G6): уходим в фон — последняя точка должна лежать в базе, иначе
    // виджет и тот, кто откроет карту позже, увидят место двухминутной давности.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_flushUnstored());
    }
    if (_posSub == null) return;
    final foreground = _appInForeground();
    if (_streamForeground == foreground) return;
    final channel = _activePairId;
    if (channel == null) return;
    // На Android поток не трогаем ни в какую сторону: он живёт
    // foreground-сервисом, и перезапуск заново показывает уведомление
    // «Геопозиция включена» — на это и жаловались. Профиль там один.
    if (Platform.isAndroid) return;
    unawaited(_restartStream(channel, foreground));
  }

  Future<void> _restartStream(String channel, bool foreground) async {
    final generation = _sessionGeneration;
    await _cancelStream();
    if (generation != _sessionGeneration || _uid.isEmpty) return;
    _activePairId = channel;
    _streamForeground = foreground;
    try {
      _posSub = Geolocator.getPositionStream(
        locationSettings: _locationSettings(),
      ).listen((pos) => _push(channel, pos), onError: _onStreamError);
    } catch (e) {
      debugPrint('LiveLocationService: перезапуск потока не вышел: $e');
    }
  }

  /// Приложение на переднем плане? Нужен, чтобы не стартовать location-FGS из
  /// фона (Android 12+ это запрещает и роняет ForegroundServiceStartNotAllowed).
  bool _appInForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null ||
        s == AppLifecycleState.resumed ||
        s == AppLifecycleState.inactive;
  }

  /// Можно ли поднимать поток прямо сейчас.
  ///
  /// Отдельно от [_appInForeground]: там неизвестное состояние считается
  /// передним планом (профиль потока при старте выбирается точным), а для
  /// запуска сервиса это как раз опасный случай — холодный старт из фонового
  /// пробуждения выглядит именно так.
  bool _canStartFgs() => fgsLocationStartAllowed(
    WidgetsBinding.instance.lifecycleState,
    android: Platform.isAndroid,
  );

  Future<void> _pushCurrent(String pairId) async {
    final generation = _sessionGeneration;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (generation != _sessionGeneration) return;
      await _push(pairId, pos);
    } catch (e) {
      debugPrint('LiveLocationService initial fix failed: $e');
    }
  }

  /// Как часто точка ложится на диск.
  ///
  /// Живая точка идёт в канал и хранения не требует. Запись нужна только тому,
  /// кто откроет карту позже, и виджету на рабочем столе — им хватает свежести
  /// в пару минут. Пока каждая точка писалась в базу, геопозиция стояла в общей
  /// очереди единственного писателя вместе с сообщениями и настроениями.
  static const Duration _storeEvery = Duration(minutes: 2);
  int? _storedAtMs;

  Future<void> _push(String channel, Position pos) async {
    final generation = _sessionGeneration;
    if (_uid.isEmpty || _activePairId != channel) return;
    myFix.value = pos;
    // Пишем только конечные числа (heading/accuracy бывают NaN/Infinity, когда
    // значение недоступно).
    final acc = pos.accuracy.isFinite ? pos.accuracy : 0.0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final point = {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': acc,
      if (pos.heading.isFinite && pos.heading >= 0) 'heading': pos.heading,
      'updatedAt': now,
    };

    // Партнёру — сразу через канал, минуя диск.
    final sealed = ForkE2E.sealPoint(channel, {
      't': 'point',
      'uid': _uid,
      ...point,
    }); // fork: нет ключа — null
    if (sealed != null) {
      await CentrifugoService().publish('loc:$channel', sealed);
    }

    // fork (UX G6): запись в базу — раз в две минуты, но последняя точка не
    // теряется: если она не попала в окно, её дописывает таймер, уход в фон
    // или остановка показа.
    if (generation != _sessionGeneration ||
        _activePairId != channel ||
        _uid.isEmpty)
      return;
    final stored = _storedAtMs;
    if (stored == null || now - stored >= _storeEvery.inMilliseconds) {
      _storeTimer?.cancel();
      _storeTimer = null;
      _unstored = null;
      _storedAtMs = now;
      if (await _data.setLivePoint(channel, _uid, point)) {
        _confirmMutual(channel, generation);
      }
    } else {
      _unstored = point;
      _unstoredChannel = channel;
      _storeTimer ??= Timer(
        Duration(milliseconds: _storeEvery.inMilliseconds - (now - stored)),
        () => unawaited(_flushUnstored()),
      );
    }
    // Точка ушла — значит передача жива (после сбоя потока и т.п.).
    if (issue.value == ShareIssue.streamFailed) issue.value = ShareIssue.none;
    // fork: «вы оба рядом с местом из вишлиста» (docs/WISHLIST.md).
    unawaited(
      WishPlaces.instance.onMyFix(
        channel: channel,
        myUid: _uid,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: acc,
      ),
    );
  }

  Timer? _storeTimer;
  Map<String, dynamic>? _unstored;
  String? _unstoredChannel;

  Future<void> _flushUnstored() async {
    _storeTimer?.cancel();
    _storeTimer = null;
    final point = _unstored, channel = _unstoredChannel;
    _unstored = null;
    if (point == null || channel == null || _uid.isEmpty) return;
    _storedAtMs = DateTime.now().millisecondsSinceEpoch;
    final generation = _sessionGeneration;
    try {
      if (await _data.setLivePoint(channel, _uid, point)) {
        _confirmMutual(channel, generation);
      }
    } catch (e) {
      debugPrint('LiveLocationService: последняя точка не записалась: $e');
    }
  }

  /// fork (D11): точка легла на сервер — значит, своя запись в канале есть.
  /// Открывает гейт, если флаг при включении не подтвердился (сбой сети):
  /// иначе человек делился бы, сам не видя партнёра до перезапуска.
  void _confirmMutual(String channel, int generation) {
    if (generation != _sessionGeneration ||
        !sharingEnabled.value ||
        _activePairId != channel) {
      return;
    }
    if (mutualChannel.value != channel) mutualChannel.value = channel;
  }

  Future<void> _cancelStream() async {
    final sub = _posSub;
    _posSub = null;
    try {
      await sub?.cancel();
    } catch (e) {
      // geolocator бросает «No active stream to cancel», если нативный стрим
      // уже снят системой — это не повод падать.
      debugPrint('LiveLocationService: отмена стрима: $e');
    }
  }

  /// Останавливает стрим. [removePoint] — удалить ли свою последнюю точку из
  /// RTDB (true при явном выключении шеринга; false при простом анбинде, чтобы
  /// партнёр видел последнее местоположение).
  // fork: logout must invalidate work synchronously, without flushing a final point.
  void stopForLogout() {
    _sessionGeneration++;
    _activePairId = null;
    _storeTimer?.cancel();
    _storeTimer = null;
    _unstored = null;
    _unstoredChannel = null;
    _storedAtMs = null;
    myFix.value = null;
    mutualChannel.value = null; // fork (D11)
    final sub = _posSub;
    _posSub = null;
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  Future<void> stopSharing({bool removePoint = false}) async {
    // fork (UX G6): простая остановка оставляет точку партнёру — пусть она
    // будет последней, а не двухминутной давности. При удалении — выбрасываем.
    if (removePoint) {
      mutualChannel.value = null; // fork (D11): партнёра больше не видно
      _storeTimer?.cancel();
      _storeTimer = null;
      _unstored = null;
      _storedAtMs = null;
    } else {
      await _flushUnstored();
    }
    await _cancelStream();
    myFix.value = null;
    final pairId = _activePairId;
    _activePairId = null;
    if (removePoint && pairId != null && _uid.isNotEmpty) {
      // pairId здесь — канал пары (_activePairId). fork (D11): сигнал
      // остановки — до удаления записи, пока сервер ещё пускает в канал.
      await _announceStop(pairId); // fork (UX G2)
      await _data.clearLivePoint(pairId, _uid);
      await CentrifugoService().release('loc:$pairId');
    }
  }

  // fork (UX G2): партнёр держит последнюю точку из канала в памяти и без
  // этого сигнала видел бы её «живой» и после «Выключить».
  Future<void> _announceStop(String channel) async {
    final sealed = ForkE2E.sealPoint(channel, {
      't': 'stop',
      'uid': _uid,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (sealed == null) return;
    try {
      await CentrifugoService().publish('loc:$channel', sealed);
    } catch (e) {
      debugPrint('LiveLocationService: сигнал остановки не ушёл: $e');
    }
  }

  // ── Чтение позиции партнёра ───────────────────────────────────────────────

  /// Поток последней точки партнёра. null — точки ещё нет. Читает из ОБЩЕГО
  /// узла пары (канонический ключ), а не из pairId активной группы.
  Stream<LivePoint?> watchPartner(String pairId, String partnerUid) {
    if (pairId.isEmpty || partnerUid.isEmpty) {
      return Stream<LivePoint?>.value(null);
    }
    final channel = _channel(pairId, partnerUid);
    // fork (D11): сам не делишься — партнёра не видно: ни подписки, ни
    // последней точки. Выключил на ходу — поток сразу отдаёт null.
    return whileMutual<LivePoint>(
      gate: _mutualGate,
      isOpen: () => _mutualOpen(channel),
      open: () => _watchPoint(channel, partnerUid),
    );
  }

  /// Поток своей последней точки в том же общем узле пары (чтобы своя аватарка
  /// рисовалась из RTDB ровно из того узла, куда мы пишем). [partnerUid] нужен
  /// для вычисления канонического ключа канала.
  Stream<LivePoint?> watchSelf(String pairId, String partnerUid) {
    if (_uid.isEmpty) return Stream<LivePoint?>.value(null);
    final channel = _channel(pairId, partnerUid);
    // fork (D11): своей записи без показа нет, а канал сервер не выдаст.
    return whileMutual<LivePoint>(
      gate: _mutualGate,
      isOpen: () => _mutualOpen(channel),
      open: () => _watchPoint(channel, _uid),
    );
  }

  /// Точка участника: сначала канал, база — как опора и совместимость.
  ///
  /// Живые точки летят публикацией в `loc:<канал>` и на диск не попадают, но
  /// партнёр может сидеть на сборке постарше — она по-прежнему пишет их в
  /// коллекцию. Читаем оба источника и показываем тот, что свежее; заодно
  /// запись из базы отдаёт последнюю точку тому, кто открыл карту только что.
  Stream<LivePoint?> _watchPoint(String channel, String uid) {
    StreamSubscription? dbSub;
    LivePoint? fromDb;
    LivePoint? fromChannel;

    void emit(void Function(LivePoint?) add) {
      final a = fromChannel;
      final b = fromDb;
      LivePoint? best;
      if (a == null) {
        best = b;
      } else if (b == null) {
        best = a;
      } else {
        best = a.updatedAt >= b.updatedAt ? a : b;
      }
      add(best);
    }

    // RT-5: уход слушателя до конца подписки не оставляет канал висеть.
    return subscribedStream<LivePoint?>(
      start: (add) {
        dbSub = _rt
            .watchLivePoint(channel, uid)
            .handleError((e) => debugPrint('live location point error: $e'))
            .listen((rec) {
              final v = rec?.data['data'];
              final had = fromDb != null; // fork (UX G2)
              fromDb = v is Map ? LivePoint.fromMap(v) : null;
              if (had && fromDb == null)
                fromChannel = null; // fork: точку убрали — показ выключен
              emit(add);
            });
      },
      subscribe: (add) =>
          CentrifugoService().subscribeRaw('loc:$channel', (raw) {
            final data = ForkE2E.openPoint(channel, raw);
            if (data == null) return;
            if ((data['uid'] ?? '').toString() != uid) return;
            if (data['t'] == 'stop') {
              // fork (UX G2): показ выключен
              fromChannel = null;
              fromDb = null;
              emit(add);
              return;
            }
            if (data['t'] != 'point') return;
            fromChannel = LivePoint.fromMap(data);
            emit(add);
          }),
      stop: () => dbSub?.cancel(),
    );
  }

  // ── Настройки геолокации (фон) ────────────────────────────────────────────

  LocationSettings _locationSettings() {
    // Профиль зависит от того, смотрит ли человек на экран: в фоне метку
    // видят изредка, а GPS будится постоянно — отсюда и стрелка на iPhone, и
    // уведомление на Android, и разряд батареи (три жалобы 21.08.2026).
    final tune = liveLocationTuning(
      foreground: _appInForeground(),
      android: Platform.isAndroid,
    );
    final accuracy = tune.highAccuracy
        ? LocationAccuracy.high
        : LocationAccuracy.medium;
    final distanceFilter = tune.distanceFilter;
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // Как часто система вообще спрашивает координату. Редкий опрос — та
        // самая экономия, ради которой раньше снимали wake lock; со снятым
        // замком фон переставал работать вовсе.
        intervalDuration: tune.interval,
        // Foreground-service держит стрим живым в фоне. Геолокатор сам
        // объявляет сервис и его тип в своём манифесте.
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: LocaleService.current.liveLocationServiceTitle,
          notificationText: LocaleService.current.liveLocationServiceText,
          enableWakeLock: tune.wakeLock,
          // fork (UX G12): смахнул — думает, что выключил, а точка уходит.
          setOngoing: true,
          // Та же монохромная иконка, что у всех уведомлений приложения
          // (FCM/локальные). Без неё geolocator ставит свой дефолт — отсюда
          // была «не та» иконка на уведомлении.
          notificationIcon: const AndroidResource(
            name: 'ic_notification',
            defType: 'drawable',
          ),
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: tune.pauseAutomatically,
        // Индикатор система показывает сама, когда действительно берёт
        // координаты в фоне. Принудительный показ держал стрелку в чужих
        // приложениях круглые сутки.
        showBackgroundLocationIndicator: tune.forceIndicator,
        allowBackgroundLocationUpdates: true,
        activityType: ActivityType.other,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }

  // ── Утилиты ───────────────────────────────────────────────────────────────

  /// Расстояние между двумя точками в метрах.
  static double distanceMeters(LatLng a, LatLng b) =>
      const Distance().as(LengthUnit.Meter, a, b);

  /// Человекочитаемая дистанция: «рядом» ближе 50 м, метры десятками,
  /// километры по правилам языка («2,9 км», «1 609 км»). Правила —
  /// `formatMapDistance`.
  static String formatDistance(double meters) {
    final s = LocaleService.current;
    return formatMapDistance(
      meters,
      lang: LocaleService.instance.language.code,
      nearby: s.liveMapNearby,
      unitM: s.unitM,
      unitKm: s.unitKm,
    );
  }
}
