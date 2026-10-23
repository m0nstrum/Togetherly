import '../../fork/watch/picture_in_picture.dart'; // fork: PLAN 3.6
import '../../fork/app_lock/app_lock.dart'; // fork: locked apps do not enter PiP
import '../../fork/watch/room_queue.dart'; // fork: PLAN 3.5
import '../../fork/ui/feedback.dart'; // fork: match persistence failures
import '../../fork/reels/matches.dart'; // fork: PLAN 3.4
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show EagerGestureRecognizer, OneSequenceGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, SystemUiOverlayStyle, SystemChrome, SystemUiMode, DeviceOrientation; // fork: ориентация
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';

import '../../fork/e2e/room_chat_ui.dart'; // fork
import '../../fork/e2e/room_chat.dart'; // fork (Rave)
import '../../fork/watch/call_screen.dart'; // fork (Rave)
import '../../fork/watch/room_live.dart'; // fork (Rave)
import '../../fork/watch/room_picker.dart'; // fork (Rave)
import '../../fork/watch/room_shell.dart'; // fork (Rave)
import '../../fork/watch/voice_status.dart'; // fork (Rave)
import '../../dict_strings.dart' show ruEn; // fork (Rave)
import 'package:pocketbase/pocketbase.dart' show ClientException; // fork (Rave)
import '../../fork/watch_proxy.dart'; // fork
import '../../fork/watch/voice_stage.dart'; // fork
import '../../fork/watch/pair_call.dart'; // fork (UX C0)
import '../../fork/e2e/reels_chat_bridge.dart'; // fork
import '../../fork/reels/tiktok_comments.dart'; // fork: комментарии TikTok
import '../../fork/flags.dart'; // fork
import '../../models/exit_guard.dart';
import '../../widgets/memory_save/floating_note.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../models/reels_source.dart';
import '../../services/reels/reels_feed.dart';
import '../../services/plus_service.dart';
import '../../services/reels/reel_save.dart';
import '../../services/reels/reels_invite.dart';
import '../../services/reels/reels_proxy.dart';
import '../../services/reels/reels_telemetry.dart';
import '../../services/watch_history_service.dart';
import '../../services/watch_room_service.dart';
import '../../services/screen_awake.dart';
import '../../services/watch_voice_service.dart';
import '../../utils/share_origin.dart';
import '../../widgets/common/m3_loading.dart';

/// Комната совместного просмотра.
///
/// Внутри крутится тот же движок, что на сайте: один канал Centrifugo, один
/// набор сообщений. Поэтому приложение и браузер попадают в одну комнату, а
/// починки источников приезжают сюда сами, без отдельной работы.
class WatchRoomScreen extends StatefulWidget {
  /// Код комнаты пары (выдаёт сервер по связи, вводить его не нужно).
  final String room;

  /// Ссылка на видео, если просмотр начали с карточки воспоминания.
  final String? videoUrl;

  /// Пара, чью историю просмотров пополняем.
  final String pairId;

  /// Ленты вдвоём: короткие ролики по очереди из лент обоих. Комната та же,
  /// а ленту выбранной площадки этого телефона держит скрытый браузер
  /// ([ReelsFeed]).
  final bool reels;

  /// Чья площадка подаёт ленту этого телефона (выбор в листе перед лентами).
  final ReelsSource reelsSource;

  /// Открыть комнату нативным окном браузера поверх приложения, а не
  /// встроенным в экран (iPhone, доля людей с сервера — `roomOpensNatively`).
  /// Встроенный браузер на iPhone терял касания у каждого четвёртого: палец
  /// сначала проходит через Flutter. У нативного окна Flutter на пути нет.
  final bool nativeWindow;

  /// Номер сборки — метка для замера касаний на странице.
  final int build;

  const WatchRoomScreen({
    super.key,
    required this.room,
    required this.pairId,
    this.videoUrl,
    this.reels = false,
    this.reelsSource = ReelsSource.shorts,
    this.nativeWindow = false,
    this.build = 0,
  });

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen> with WidgetsBindingObserver {
  bool _loading = true;

  /// Страница комнаты: ей уходит состояние звонка, от неё приходят нажатия.
  InAppWebViewController? _web;

  /// Своё подключение к каналу комнаты — рядом с тем, что держит страница
  /// внутри WebView. Второе соединение нужно потому, что голос идёт мимо
  /// браузера: WebRTC поднимает приложение, а сигналинг живёт в том же канале.
  // fork (UX C0): своего канала у экрана больше нет — его держит ForkPairCall.
  WatchVoiceService? _voice;

  /// Лента площадки этого телефона — только в режиме лент.
  ReelsFeed? _feed;

  /// Комната идёт нативным окном. Сбрасывается, если окно не открылось:
  /// тогда комната встаёт прежним встроенным браузером.
  late bool _native = widget.nativeWindow && !widget.reels;

  /// Нативное окно комнаты и признак, что закрываем его сами.
  _RoomWindow? _window;
  bool _leaving = false;

  // fork (комната как в Rave, 22.10): в встроенном окне своя раскладка —
  // шапка, окно видео, «что играет» и чат с событиями (lib/fork/watch/room_shell.dart).
  bool get _shell => !_native && !widget.reels;
  late final ForkRoomLive _live = ForkRoomLive(partnerName: () => ForkPairCall.instance.partnerName);
  RoomChat? _chat;
  bool _chatStarting = false;
  int _seenNotice = 0;
  int _seenPick = 0;
  int _seenFull = 0;
  bool _picking = false;
  final _pip = ForkPictureInPicture.instance;
  int _seenPipClose = 0;
  bool get _videoOnly => _pip.ownedBy(this) && _pip.videoOnly;
  void _onPip() {
    if (!mounted || !_pip.ownedBy(this)) return;
    if (_seenPipClose != _pip.closedSequence) {
      _seenPipClose = _pip.closedSequence;
      unawaited(_leave());
    }
    setState(() {});
  }
  bool? _wasLandscape;
  bool _orientationLocked = false;
  DateTime? _invitedAt;

  @override
  void initState() {
    super.initState();
    _seenPipClose = _pip.closedSequence;
    _pip.addListener(_onPip);
    if (_native) {
      // Окно показывает сама система поверх экрана — открываем после первого
      // кадра, когда у маршрута уже есть место и отступы.
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_openWindow()));
    }
    // В комнате смотрят фильм и не трогают экран: без удержания он гаснет
    // по системному таймеру (жалоба 12.10.2026). Встроенный браузер экран
    // сам не держит, а играет ли ролик, знает только страница, поэтому
    // держим всё время, пока комната открыта.
    ScreenAwake.hold(this);
    unawaited(ForkWatchProxy.enable()); // fork (S11): ролики через свой сервер
    unawaited(_openVoice());
    WidgetsBinding.instance.addObserver(this);
    if (_shell) unawaited(_startChat()); // fork (Rave)
    if (_shell) ForkVoiceStatus.roomOpen.value = true; // fork (Rave): звонок — в шапке комнаты
    _live.addListener(_onLive); // fork (Rave)
    if (widget.reels) unawaited(_startFeed());
    if (widget.reels) unawaited(_reelsChat.start()); // fork: чат ленты на ключе сессии
    // Ленту запускает купивший — он и зовёт партнёра: тому придёт пуш
    // «Аня зовёт смотреть TikTok», по которому он войдёт без своего Плюса.
    if (widget.reels && PlusService.instance.active) {
      unawaited(_inviteUnlessJoining()); // fork
    }
  }

  /// fork: в форке Плюс у всех, и вошедший по зову звал бы в ответ —
  /// пригласивший получал «Партнёр зовёт смотреть». Партнёр уже зовёт —
  /// значит, мы входим к нему, звать некого.
  Future<void> _inviteUnlessJoining() async {
    if (await ReelsInvite.active(widget.pairId) != null) return;
    if (!mounted) return;
    _invited = true;
    await ReelsInvite.send(widget.pairId, widget.reelsSource);
  }

  bool _invited = false;

  /// fork: комментарии TikTok для ленты — браузер на tiktok.com по первому вопросу.
  ForkTikTokComments? _tiktok;

  // fork (E2E §10.1): переписку ленты шифрует приложение, страница рисует.
  late final ForkReelsChatBridge _reelsChat = ForkReelsChatBridge(
    room: widget.room,
    groupId: widget.pairId,
    eval: (js) async {
      await _web?.evaluateJavascript(source: js);
    },
  );

  /// Скрытая страница раскачивается несколько секунд — поднимаем её сразу,
  /// пока грузится комната. Посредник для TikTok нужен обоим: ролик из ленты
  /// партнёра играет и у того, кто сам выбрал другую площадку.
  Future<void> _startFeed() async {
    final watch = ReelsWatch(source: widget.reelsSource.key, started: DateTime.now());
    _reelsWatch = watch;
    _reelsStall = Timer(ReelsWatch.limit + const Duration(seconds: 1), _checkReelsStall);
    await ReelsProxy.enable();
    if (!mounted) return;
    final feed = ReelsFeed(widget.reelsSource, onIds: _pushFeed, onThumbs: _pushThumbs, watch: watch);
    _feed = feed;
    await feed.start();
  }

  /// Как собирается своя лента — для отчёта, если ролики так и не придут.
  ReelsWatch? _reelsWatch;
  Timer? _reelsStall;

  /// Свёрнутое приложение лента не грузит, и отчёт о такой «застрявшей»
  /// ленте врал бы: после сворачивания его не шлём.
  bool _reelsLeftApp = false;

  void _checkReelsStall() {
    final watch = _reelsWatch;
    if (!mounted || watch == null || _reelsLeftApp) return;
    final report = watch.check(
      DateTime.now(),
      proxyOn: ReelsProxy.on,
      blocked: ReelsProxy.blocked,
      proxyError: ReelsProxy.lastError,
    );
    if (report != null) ReelsTelemetry.stalled(report);
  }

  /// Свёрнутое приложение: ленты засыпают. Плееры страницы и скрытая лента
  /// иначе крутят видео, пока человека нет, а при возврате просыпаются разом —
  /// отсюда лаги после разворота (жалоба 04.10.2026).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.reels) return;
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state != AppLifecycleState.resumed && !away) return;
    if (away) _reelsLeftApp = true;
    unawaited(_web?.evaluateJavascript(source: 'window.reelsSleep && window.reelsSleep(${away ? 'true' : 'false'})'));
    unawaited(away ? (_feed?.sleep() ?? Future<void>.value()) : (_feed?.wake() ?? Future<void>.value()));
  }

  /// Ролик в лентах идёт во весь экран, под строку состояния. Странице
  /// нужно знать, где кончаются строка и системные кнопки: env() в WebView
  /// отвечает по-разному, поэтому отступы передаём сами.
  String _insetScript(EdgeInsets pad) => '(function(){var s=document.documentElement.style;'
      "s.setProperty('--app-top','${pad.top.toStringAsFixed(1)}px');"
      "s.setProperty('--app-bottom','${pad.bottom.toStringAsFixed(1)}px');})();";

  /// Свежие номера ленты — странице, которая ждёт первый ролик.
  void _pushFeed(List<String> ids) {
    final web = _web;
    if (web == null || ids.isEmpty) return;
    unawaited(web.evaluateJavascript(source: 'window.reelsFeedPush && window.reelsFeedPush(${jsonEncode(ids)})'));
  }

  /// Обложки роликов копятся здесь: лента может принести их раньше, чем
  /// загрузится страница, — тогда отдаём их в [_onPageLoaded].
  final Map<String, String> _thumbs = {};

  void _pushThumbs(Map<String, String> thumbs) {
    _thumbs.addAll(thumbs);
    if (_thumbs.length > 400) _thumbs.remove(_thumbs.keys.first);
    final web = _web;
    if (web == null) return;
    unawaited(web.evaluateJavascript(source: 'window.reelsThumbsPush && window.reelsThumbsPush(${jsonEncode(thumbs)})'));
  }

  /// Голос поднимается ЗАРАНЕЕ, а не по нажатию: канал должен слушать зов
  /// партнёра с первой секунды, иначе его «voice-hello» никто не поймает и
  /// звонок будет уходить в пустоту.
  Future<void> _openVoice() async {
    // fork (UX C0): звонок пары один на всё приложение (ForkPairCall): из
    // комнаты, ленты и чата звонят одним и тем же, разговор переживает уход
    // с экрана, входящий и плашка висят поверх любого экрана.
    final voice = await ForkPairCall.instance.bind(widget.pairId, room: widget.room);
    if (voice == null) {
      // fork (UX L3): не сдаёмся молча — пробуем снова, звонок скажет причину.
      if (mounted) {
        Future<void>.delayed(const Duration(seconds: 5), () {
          if (mounted && _voice == null) unawaited(_openVoice());
        });
      }
      return;
    }
    if (!mounted) return;
    voice.addListener(_onVoiceChanged);
    setState(() => _voice = voice);
    _pushVoice();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
    _pushVoice();
  }

  /// Отдаёт странице состояние звонка.
  ///
  /// Кнопка живёт в шапке комнаты и красится её токенами, поэтому приложение
  /// только рассказывает, что происходит: покой, ждём ответа, говорим, не
  /// вышло. Имена состояний и действий разбирает `voiceBridge` в `room.js`,
  /// сверяет их `test/screens/watch_room_voice_bridge_test.dart`.
  void _pushVoice() {
    final web = _web;
    if (web == null) return;
    final voice = _voice;
    final state = switch (voice?.state) {
      null || VoiceCallState.off => 'off',
      VoiceCallState.connecting => 'connecting',
      VoiceCallState.live => 'live',
      VoiceCallState.failed => 'failed',
    };
    final data = jsonEncode({'state': state, 'micOn': voice?.micOn ?? true, 'speakerOn': voice?.speakerOn ?? true});
    unawaited(web.evaluateJavascript(source: 'window.watchVoiceState && window.watchVoiceState($data)'));
  }

  /// Нажатие на странице: позвонить, положить трубку, приглушить микрофон.
  Future<void> _onVoiceAction(String action) async {
    final voice = _voice;
    // Канал ещё не поднялся — звонить некуда, страница просто останется
    // в покое: своего состояния она не выдумывает.
    if (voice == null) {
      // fork (UX L3): раньше кнопка молчала.
      if (action == 'call') {
        _say(voiceStageText(VoiceStage.failed, VoiceProblem.noChannel));
        unawaited(_openVoice());
      }
      return;
    }
    switch (action) {
      case 'call':
        // fork (UX L2): после «не вышло» — звоним заново.
        if (voice.state == VoiceCallState.failed) {
          await voice.start();
        } else if (!voice.active) {
          await _toggleVoice();
        }
      case 'hangup':
        if (voice.active) await voice.stop();
      case 'mic':
        voice.toggleMic();
    }
    _pushVoice();
  }

  /// Позвонить или положить трубку. Микрофон спрашивает сам WebRTC; отказ
  /// оставляет комнату как была.
  Future<void> _toggleVoice() async {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active) {
      await voice.stop();
    } else {
      await voice.start(); // fork: отказ в микрофоне показывает плашка звонка
    }
  }

  // ── нативное окно (iPhone) ───────────────────────────────────────────────

  /// Настройки браузера комнаты — одни на оба окна.
  InAppWebViewSettings _webSettings() => InAppWebViewSettings(
    // Видео должно запускаться командой партнёра, а не только пальцем.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    javaScriptEnabled: true,
    // fork (C3): external pages and video iframes cannot call native bridges.
    javaScriptHandlersForMainFrameOnly: true,
    javaScriptHandlersOriginAllowList: {'^https://${RegExp.escape(WatchRoomService.siteHost)}\$'},
    // Под нативным окном лежит экран приложения, просвечивать ему незачем.
    transparentBackground: !_native,
    supportZoom: false,
    // Движок браузеров на Android один на все окна приложения: лента держит
    // в нём три плеера и скрытую страницу площадки. Без флага его гибель от
    // нехватки памяти уносила приложение целиком (обращение 297).
    useOnRenderProcessGone: true,
  );

  /// Номер жизни страницы: новый номер ставит её заново.
  int _webLife = 0;

  /// Движок браузеров упал или его убила система: страница мертва. Ставим
  /// новую, комната подключится к каналу сама.
  void _onRendererGone() {
    if (!mounted) return;
    setState(() {
      _web = null;
      _webLife++;
      _loading = true;
    });
  }

  /// Скрипты, которые страница получает до своей загрузки.
  UnmodifiableListView<UserScript> _scripts(EdgeInsets pad) => UnmodifiableListView([
    // fork (C3): имя и признак приложения; пропуск выдаёт нативный мост.
    UserScript(
      source: WatchRoomService.authScript(
        name: PocketBaseService().userName,
      ),
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    // fork (E2E §10.1): чат комнаты — в приложении, страница только плеер.
    if (!_native) // и в ленте: её чат тоже держит приложение
      UserScript(source: forkNativeChatScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
    // fork (Rave): страница — только окно видео, остальное рисует приложение.
    if (_shell)
      UserScript(
        source: 'window.__forkShell=true;window.__forkPartner=${jsonEncode(ForkPairCall.instance.partnerName)};',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    // Лента идёт под строку состояния, нативное окно — во весь экран: обеим
    // страницам отступы сообщаем сами.
    if (widget.reels || _native)
      UserScript(source: _insetScript(pad), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
  ]);

  /// Открывает комнату нативным окном. Не открылось — встраиваем как раньше:
  /// комната важнее способа её показать.
  Future<void> _openWindow() async {
    if (!mounted || _window != null) return;
    final window = _RoomWindow(
      initialUserScripts: _scripts(MediaQuery.paddingOf(context)),
      onCreated: _wire,
      onLoaded: _onPageLoaded,
      onClosed: _onWindowClosed,
    );
    _window = window;
    try {
      await window.openUrlRequest(
        urlRequest: URLRequest(url: WebUri(_url)),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            // Шапку рисует сама страница: панель браузера ей не нужна.
            hideToolbarTop: true,
            hideUrlBar: true,
            hideProgressBar: true,
            hideCloseButton: true,
            // «Поверх экрана», а не «вместо»: иначе приложение считает себя
            // свёрнутым, гасит отрисовку и присутствие, и звонок рвётся.
            presentationStyle: ModalPresentationStyle.OVER_FULL_SCREEN,
            transitionStyle: ModalTransitionStyle.CROSS_DISSOLVE,
          ),
          webViewSettings: _webSettings(),
        ),
      );
    } catch (e) {
      debugPrint('WatchRoom: нативное окно не открылось — $e');
      _window = null;
      _web = null;
      if (mounted) setState(() => _native = false);
      if (mounted) unawaited(_startChat()); // fork (Rave): встали встроенным — чат наш
    }
  }

  /// Окно закрылось. Сами закрывали — маршрут снимет тот, кто закрывал;
  /// закрыла система — уходим из комнаты следом, под окном пустой экран.
  void _onWindowClosed() {
    _window = null;
    _web = null;
    if (_leaving || !mounted) return;
    _leaving = true;
    _dropRoute();
  }

  /// Выйти из комнаты: в нативном режиме сперва убрать окно.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _closeWindow();
    if (mounted) _dropRoute();
  }

  Future<void> _closeWindow() async {
    final window = _window;
    _window = null;
    if (window == null) return;
    try {
      if (window.isOpened()) await window.close();
    } catch (e) {
      debugPrint('WatchRoom: окно не закрылось — $e');
    }
    window.dispose();
  }

  /// Снимает свой маршрут, даже если он уже не верхний.
  void _dropRoute() {
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  /// Поверх комнаты открыли другой экран (пуш, ссылка). Под нативным окном
  /// его не видно, поэтому комната уступает: окно закрывается.
  Animation<double>? _covered;

  void _onCovered(AnimationStatus status) {
    if (status == AnimationStatus.forward && _pip.ownedBy(this) && _pip.videoOnly) _pip.release(this);
    if (!_native || _leaving || status != AnimationStatus.forward) return;
    unawaited(_leave());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context)?.secondaryAnimation;
    if (identical(next, _covered)) return;
    _covered?.removeStatusListener(_onCovered);
    _covered = next;
    next?.addStatusListener(_onCovered);
  }

  /// Короткое сообщение человеку. Плашку Flutter под нативным окном не
  /// видно, поэтому там её показывает сама страница (`window.roomNote`).
  void _say(String text) {
    if (!mounted || _videoOnly) return;
    if (_native) {
      unawaited(
        _web?.evaluateJavascript(source: 'window.roomNote && window.roomNote(${jsonEncode(text)})') ??
            Future<void>.value(),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    // fork (Rave): чат сеанса, события и ориентация — вернуть как было.
    _pip.removeListener(_onPip);
    _pip.release(this);
    _live.removeListener(_onLive);
    _live.dispose();
    ForkVoiceStatus.roomOpen.value = false;
    _chat?.dispose();
    if (_orientationLocked) unawaited(SystemChrome.setPreferredOrientations(const []));
    if (_wasLandscape == true) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(ForkWatchProxy.disable()); // fork
    _covered?.removeStatusListener(_onCovered);
    unawaited(_closeWindow());
    ScreenAwake.release(this);
    WidgetsBinding.instance.removeObserver(this);
    _voice?.removeListener(_onVoiceChanged); // fork (UX C0): звонок живёт дальше, его держит ForkPairCall
    _reelsStall?.cancel();
    unawaited(_feed?.dispose() ?? Future<void>.value());
    if (widget.reels) unawaited(ReelsProxy.disable());
    if (_invited) unawaited(ReelsInvite.stop(widget.pairId));
    if (widget.reels) _reelsChat.dispose(); // fork
    unawaited(_tiktok?.dispose() ?? Future<void>.value()); // fork
    super.dispose();
  }

  /// Адрес открытой комнаты: с роликом, если пришли из карточки или карусели,
  /// и со своим именем — иначе страница подписывает обоих «Гость».
  String get _url => WatchRoomService.siteUrl(
    widget.room,
    src: widget.videoUrl,
    name: PocketBaseService().userName,
    reels: widget.reels,
    feed: widget.reels ? widget.reelsSource.key : null,
    build: widget.build,
    nativeWindow: _native,
  );

  /// Ссылка для партнёра — без ролика и без имени: он войдёт в ту же комнату,
  /// получит источник от нас по каналу и подпишется своим именем.
  String get _inviteUrl => WatchRoomService.siteUrl(widget.room);

  Future<void> _share() async {
    // Без якоря на iPad лист не открывается вовсе, и кнопка выглядит мёртвой —
    // ровно за это прилетал реджект 2.1(a) по «Scan to Connect».
    await Share.share(_inviteUrl, sharePositionOrigin: shareOriginFromContext(context));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    _say(LocaleService.current.linkCopied);
  }

  /// Когда последний раз нажимали «назад».
  ///
  /// Выход из комнаты останавливает кино у обоих, и промахнуться легко:
  /// «случайно нажимаешь и тебя выбрасывает с комнаты» (просьба пары,
  /// 20.09.2026). Первое нажатие предупреждает, второе выпускает.
  DateTime? _backAt;

  // fork (UX V7): «назад» в полном экране выводит из полного экрана, а не
  // из комнаты — иначе кино останавливалось у обоих.
  Future<void> _onBack() async {
    // fork (Rave): «назад» во весь экран возвращает к комнате.
    if (_shell && _wasLandscape == true) {
      _fullscreen(false);
      return;
    }
    final web = _web;
    if (web != null && !widget.reels) {
      try {
        final r = await web.evaluateJavascript(
          source: 'window.forkExitCinema ? window.forkExitCinema() : false',
        );
        if (r == true) return;
      } catch (e) {
        debugPrint('WatchRoom: полный экран не ответил: $e');
      }
    }
    if (_allowLeave() && mounted) await _leave();
  }

  /// Отпускать ли из комнаты. Первое нажатие показывает подсказку.
  bool _allowLeave() {
    if (ForkFlags.singleBackExit) return true; // fork: выход с первого «назад»
    final now = DateTime.now();
    if (exitOnBack(lastPress: _backAt, now: now)) return true;
    _backAt = now;
    if (_native) {
      _say(LocaleService.current.watchRoomBackAgain);
      return false;
    }
    showFloatingNote(
      context,
      LocaleService.current.watchRoomBackAgain,
      icon: Icons.logout_rounded,
      duration: kExitWindow,
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_onBack()); // fork (UX V7)
      },
      // В лентах строка состояния светлыми значками по чёрному.
      child: widget.reels
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: _roomScaffold(context, s, cs),
            )
          : _roomScaffold(context, s, cs),
    );
  }

  Widget _roomScaffold(BuildContext context, AppStrings s, ColorScheme cs) {
    return Scaffold(
      // Ленты идут по чёрному полю во весь экран: светлая полоса над роликом
      // выглядела бы чужой рамкой.
      backgroundColor: _videoOnly || widget.reels || (_shell && MediaQuery.orientationOf(context) == Orientation.landscape) ? Colors.black : cs.surface, // fork (Rave)
      // Своей шапки нет: её рисует страница комнаты — «назад», код,
      // «скопировать», «поделиться», звонок и сворачивание. Две шапки подряд
      // съедали высоту и повторяли одно и то же (28.09.2026).
      body: SafeArea(
        // В лентах ролик заходит под строку состояния, как в TikTok: чёрная
        // полоса над ним читалась пустой шапкой. Отступ кнопкам страница
        // берёт из `_insetScript`.
        top: !widget.reels && !_videoOnly,
        bottom: false,
        // Нативное окно комнаты система показывает поверх этого экрана: под
        // ним остаётся только ожидание, пока окно открывается и закрывается.
        child: _native ? Center(child: M3Loading(color: cs.primary)) : _shell ? _shellBody(context) : Stack( // fork (Rave)
          children: [
            _webView(context), // fork (Rave): один и тот же браузер в обеих раскладках
            if (_loading) Center(child: M3Loading(color: Theme.of(context).colorScheme.primary)),
            if (!widget.reels) ForkRoomChatOverlay(room: widget.room, groupId: widget.pairId), // fork
            // fork (UX C0): входящий и плашка звонка — поверх всего приложения (ForkPairCall).
          ],
        ),
      ),
    );
  }

  // fork (Rave): браузер комнаты вынесен из Stack, чтобы стоять и в новой раскладке.
  Widget _webView(BuildContext context) {
    return InAppWebView(
              key: ValueKey<int>(_webLife),
              initialUrlRequest: URLRequest(url: WebUri(_url)),
              // Касание в зоне комнаты сразу уходит браузеру, не дожидаясь арены
              // жестов Flutter: на iPhone после рекламы оно иначе терялось, и
              // страница не отвечала ни на что (обращения 164, 178, 183, 190).
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
              },
              initialUserScripts: _scripts(MediaQuery.paddingOf(context)),
              initialSettings: _webSettings(),
              onWebViewCreated: _wire,
              onLoadStop: (c, _) => _onPageLoaded(c),
              onRenderProcessGone: (_, _) => _onRendererGone(),
              onReceivedHttpAuthRequest: (_, ch) async => ForkWatchProxy.answer(ch), // fork
            );
  }

  // ── fork: комната как в Rave ─────────────────────────────────────────────

  /// Шифрованный чат сеанса — один на вертикальную раскладку и полный экран.
  Future<void> _startChat() async {
    if (!_shell || _chat != null || _chatStarting) return;
    setState(() => _chatStarting = true);
    final chat = await forkStartRoomChat(widget.room, widget.pairId);
    if (!mounted) {
      chat?.dispose();
      return;
    }
    setState(() {
      _chat = chat;
      _chatStarting = false;
    });
  }

  void _onLive() {
    if (!mounted) return;
    if (_live.noticeSeq != _seenNotice) {
      _seenNotice = _live.noticeSeq;
      _say(_live.notice);
    }
    if (_live.pickSeq != _seenPick) {
      _seenPick = _live.pickSeq;
      unawaited(_pick());
    }
    if (_live.fullscreenSeq != _seenFull) {
      _seenFull = _live.fullscreenSeq;
      _fullscreen(true);
    }
    if (_live.partnerHere && _invitedAt != null) setState(() => _invitedAt = null);
  }

  Future<Object?> _js(String source) async {
    final web = _web;
    if (web == null || _loading) {
      _say(ruEn('Комната ещё открывается — секунду', 'The room is still opening — one moment'));
      return null;
    }
    try {
      return await web.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('WatchRoom: страница не ответила: $e');
      return null;
    }
  }

  /// Лист «Что смотрим?»: ссылка, недавнее, свои ролики, файл.
  Future<void> _enterPip() async {
    if (_pip.busy || !_shell || _loading || !_live.hasVideo) return;
    final lock = ForkAppLock.instance;
    await lock.load();
    if (!mounted) return;
    if (!lock.ready) {
      _say(ruEn('Не удалось проверить настройки замка — повторите попытку.', 'Could not check app lock settings — please retry.'));
      return;
    }
    if (lock.enabled) {
      _say(ruEn('PiP недоступен с включённым замком приложения.', 'PiP is unavailable while app lock is on.'));
      return;
    }
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _seenPipClose = _pip.closedSequence;
    final result = await _pip.enter(this, canEnter: () => mounted &&
      ModalRoute.of(context)?.isCurrent == true && lock.ready && !lock.enabled);
    if (!mounted || ModalRoute.of(context)?.isCurrent != true || result == ForkPipOutcome.entered) return;
    if (result == ForkPipOutcome.unsupported) {
      _say(ruEn('На этом устройстве PiP недоступен.', 'PiP is unavailable on this device.'));
      return;
    }
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: Text(ruEn('Не удалось открыть PiP', 'Could not open PiP')),
      content: Text(ruEn('Проверьте разрешение «Картинка в картинке» для Tethered.', 'Check the Picture-in-picture permission for Tethered.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(ruEn('Закрыть', 'Close'))),
        TextButton(onPressed: () async {
          Navigator.pop(context);
          try { await ForkPictureInPicture.settings(); }
          catch (_) { if (mounted) _say(ruEn('Настройки PiP недоступны.', 'PiP settings are unavailable.')); }
        }, child: Text(ruEn('Настройки', 'Settings'))),
      ]));
  }

  Future<void> _queue() => Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ForkRoomQueueScreen(live: _live,
      onAdd: () => unawaited(_pick(enqueue: true)),
      onPlay: (id) => unawaited(_js('window.forkRoom && window.forkRoom.queuePlay(${jsonEncode(id)})')),
      onRemove: (id) => unawaited(_js('window.forkRoom && window.forkRoom.queueRemove(${jsonEncode(id)})')),
      onNext: () => unawaited(_js('window.forkRoom && window.forkRoom.queueNext()')))));

  Future<void> _pick({bool enqueue = false}) async {
    if (_picking) return;
    _picking = true;
    final pick = await showForkRoomPicker(context, groupId: widget.pairId);
    _picking = false;
    if (pick == null || !mounted) return;
    if (enqueue) {
      if (pick.file) {
        _say(ruEn('Локальный файл нельзя добавить в общую очередь — выберите ссылку.',
          'A local file cannot join the shared queue — choose a link.'));
      } else {
        await _js('window.forkRoom && window.forkRoom.queueAdd(${jsonEncode(pick.url)})');
      }
      return;
    }
    if (pick.file) {
      await _js('window.forkRoom && window.forkRoom.file()');
      return;
    }
    // Отказ страница объясняет сама (статус → [_say]).
    await _js('window.forkRoom ? window.forkRoom.play(${jsonEncode(pick.url)}) : false');
  }

  /// Во весь экран — поворотом, как в Rave и YouTube; выход — обратно
  /// вертикально. Повернул телефон сам — раскладка следует за ним.
  void _fullscreen(bool on) {
    _orientationLocked = true;
    unawaited(SystemChrome.setPreferredOrientations(on
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]));
  }

  void _syncImmersive(bool land) {
    if (_wasLandscape == land) return;
    final first = _wasLandscape == null;
    _wasLandscape = land;
    if (first && !land) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(SystemChrome.setEnabledSystemUIMode(land ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
    });
  }

  /// Позвать партнёра в комнату: ему придёт уведомление «зовёт смотреть».
  Future<void> _invite() async {
    setState(() => _invitedAt = DateTime.now());
    try {
      await PocketBaseService().pb.send(
        '/api/fork/ring',
        method: 'POST',
        body: {'group_id': widget.pairId, 'kind': 'watch'},
      );
      _say(ruEn('Позвали — партнёру придёт уведомление', 'Invited — your partner gets a notification'));
    } on ClientException catch (e) {
      if (e.statusCode == 429) {
        _say(ruEn('Уже позвали — подождите немного', 'Already invited — give it a moment'));
      } else {
        if (mounted) setState(() => _invitedAt = null);
        _say(ruEn('Не получилось позвать — проверьте связь', 'Couldn’t invite — check your connection'));
      }
    }
    Future<void>.delayed(const Duration(minutes: 1), () {
      if (mounted && _invitedAt != null) setState(() => _invitedAt = null);
    });
  }

  /// Трубка в шапке: позвонить, а во время разговора — открыть звонок.
  void _callTap() {
    final v = _voice;
    if (v != null && v.stage != VoiceStage.idle) {
      unawaited(ForkCallScreen.open(
        Navigator.of(context, rootNavigator: true),
        voice: v,
        partnerName: ForkPairCall.instance.partnerName,
        onRetry: () async => v.start(),
      ));
      return;
    }
    unawaited(_onVoiceAction('call'));
  }

  Widget _shellBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final land = box.maxWidth > box.maxHeight;
        if (!_videoOnly) _syncImmersive(land);
        final video = land || _videoOnly
            ? Rect.fromLTWH(0, 0, box.maxWidth, box.maxHeight)
            : Rect.fromLTWH(0, ForkRoomTopBar.heightFor(context), box.maxWidth, box.maxWidth * 9 / 16);
        final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        final cs = Theme.of(context).colorScheme;
        return Stack(
          children: [
            // Браузер всегда первым ребёнком: при повороте он не пересоздаётся.
            Positioned.fromRect(
              rect: video,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _webView(context),
                    if (_loading) Center(child: M3Loading(color: cs.primary)),
                  ],
                ),
              ),
            ),
            if (!land && !_videoOnly) ...[
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: ForkRoomTopBar.heightFor(context),
                child: ListenableBuilder(
                  listenable: _live,
                  builder: (_, _) => ForkRoomTopBar(
                    partnerName: ForkPairCall.instance.partnerName,
                    partnerHere: _live.partnerHere,
                    invited: _invitedAt != null,
                    onBack: () => unawaited(_onBack()),
                    onInvite: () => unawaited(_invite()),
                    voice: _voice,
                    onCall: _callTap,
                    onShare: () => unawaited(_share()),
                    onCopy: () => unawaited(_copy()),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: video.bottom,
                bottom: 0,
                child: Column(
                  children: [
                    // Пока печатают, полоса уступает место переписке.
                    if (!typing)
                      ListenableBuilder(
                        listenable: _live,
                        builder: (_, _) => ForkNowPlaying(
                          live: _live,
                          onPick: () => unawaited(_pick()),
                          onQueue: () => unawaited(_queue()),
                          onPip: defaultTargetPlatform == TargetPlatform.android ? () => unawaited(_enterPip()) : null,
                          onToggle: () => unawaited(_js('window.forkRoom && window.forkRoom.toggle()')),
                          onTogether: () => unawaited(_js('window.forkRoom && window.forkRoom.together()')),
                          onPauseBoth: () => unawaited(_js('window.forkRoom && window.forkRoom.pauseBoth()')),
                          onFullscreen: () => _fullscreen(true),
                        ),
                      ),
                    Divider(height: 1, color: cs.outlineVariant),
                    Expanded(
                      child: ForkRoomChatPanel(chat: _chat, live: _live, starting: _chatStarting),
                    ),
                  ],
                ),
              ),
            ] else if (!_videoOnly) ...[
              Positioned(
                left: 8,
                top: 8,
                child: IconButton.filledTonal(
                  tooltip: ruEn('Свернуть', 'Exit full screen'),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                  icon: const Icon(Icons.fullscreen_exit_rounded),
                  onPressed: () => _fullscreen(false),
                ),
              ),
              if (_chat != null) ForkRoomChatOverlay(room: widget.room, groupId: widget.pairId, chat: _chat),
            ],
          ],
        );
      },
    );
  }

  /// Мосты страницы к приложению — одни на встроенный браузер и на нативное
  /// окно.
  void _wire(InAppWebViewController c) {
    _web = c;
    // fork (C3): only a ticket for this screen's room crosses the bridge.
    c.addJavaScriptHandler(
      handlerName: 'forkWatchTicket',
      callback: (args) async {
        final url = await c.getUrl();
        if (url == null || url.scheme != 'https' || url.host != WatchRoomService.siteHost ||
            !url.path.startsWith('/watch/')) {
          return null;
        }
        final guest = args.isNotEmpty && args.first is String ? args.first as String : '';
        try {
          return await WatchRoomService.ticket(widget.room, guest);
        } on ClientException catch (e) {
          final reason = e.response['error'];
          return {'ok': false, 'error': const ['auth_required', 'not_member', 'not_found'].contains(reason) ? reason : 'ticket_failed'};
        } catch (_) {
          return {'ok': false, 'error': 'ticket_failed'};
        }
      },
    );
    // fork (Rave): что происходит в окне видео — полосе и чату.
    c.addJavaScriptHandler(
      handlerName: 'forkRoom',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          _live.handle(Map<String, dynamic>.from(args.first as Map));
        }
        return null;
      },
    );
    // fork: реплика ленты — шифрует приложение (ForkReelsChatBridge).
    c.addJavaScriptHandler(
      handlerName: 'forkChat',
      callback: (args) {
        final m = args.isNotEmpty && args.first is Map ? args.first as Map : const {};
        if (widget.reels) unawaited(_reelsChat.send('${m['text'] ?? ''}'));
        return null;
      },
    );
    // Кнопка звонка стоит в шапке комнаты, а связь поднимает
    // приложение: у страницы нет ни микрофона пары, ни сигналинга.
    // Кнопки шапки страницы: «назад», «скопировать», «поделиться».
    c.addJavaScriptHandler(
      handlerName: 'watchBack',
      callback: (_) {
        if (mounted && _allowLeave()) unawaited(_leave());
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'watchCopy',
      callback: (_) {
        _copy();
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'watchShare',
      callback: (_) {
        _share();
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'watchVoice',
      callback: (args) {
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        unawaited(_onVoiceAction((info['action'] ?? '').toString()));
        return null;
      },
    );
    // Ленты: страница просит номера роликов, сообщает, что играет
    // из нашей ленты, и отправляет ссылку на ролик.
    c.addJavaScriptHandler(
      handlerName: 'reelsFeed',
      callback: (args) async {
        final feed = _feed;
        if (feed == null) return const <String>[];
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        final need = int.tryParse('${info['need'] ?? 8}') ?? 8;
        return feed.take(need.clamp(1, 20));
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'reelsWatching',
      callback: (args) {
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        unawaited(_feed?.watching((info['id'] ?? '').toString()) ?? Future<void>.value());
        return null;
      },
    );
    // fork: комментарии TikTok к ролику (лист в ленте, fork-comments.js).
    c.addJavaScriptHandler(
      handlerName: 'reelsComments',
      callback: (args) async {
        if (!widget.reels) return const {'ok': false, 'why': 'failed'};
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        final tiktok = _tiktok ??= ForkTikTokComments();
        return tiktok.page(
          id: '${info['id'] ?? ''}',
          cid: '${info['cid'] ?? ''}',
          cursor: int.tryParse('${info['cursor'] ?? 0}') ?? 0,
        );
      },
    );
    // «Обновить рекомендации»: скрытая лента начинается заново.
    c.addJavaScriptHandler(
      handlerName: 'reelsRefresh',
      callback: (_) async {
        await _feed?.refresh();
        return null;
      },
    );
    // fork: fixed screen pair; no group, author, URL or account token from JS.
    c.addJavaScriptHandler(
      handlerName: 'forkReelsMatch',
      callback: (args) async {
        final url = await c.getUrl();
        if (!widget.reels || url == null || url.scheme != 'https' ||
            url.host != WatchRoomService.siteHost || !url.path.startsWith('/watch/reels/')) {
          return {'ok': false};
        }
        final value = args.isNotEmpty && args.first is Map ? args.first as Map : const {};
        final clip = value['key'], reaction = value['reaction'];
        if (clip is! String || reaction is! String) return {'ok': false};
        Future<void> save() => ForkReelsMatches.instance.save(widget.pairId, clip, reaction);
        try { await save(); return {'ok': true}; }
        catch (e) {
          if (mounted) ForkNotice.failure(context, ForkFailure.of(e), retry: () async {
            try { await save(); }
            catch (error) { if (mounted) ForkNotice.failure(context, ForkFailure.of(error)); }
          });
          return {'ok': false};
        }
      },
    );
    // Закладка: ролик ложится в ленту воспоминаний пары.
    c.addJavaScriptHandler(
      handlerName: 'reelsSave',
      callback: (args) async {
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        final ok = await ReelSave.save(
          groupId: widget.pairId,
          key: (info['key'] ?? '').toString(),
        );
        return {'ok': ok};
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'reelsShare',
      callback: (args) async {
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        final url = (info['url'] ?? '').toString();
        if (url.isEmpty || !mounted) return null;
        await Share.share(url, sharePositionOrigin: shareOriginFromContext(context));
        return null;
      },
    );
    // Комната сама сообщает, что включили: иначе приложение не знает,
    // что происходит внутри встроенного браузера.
    c.addJavaScriptHandler(
      handlerName: 'watchSource',
      callback: (args) {
        final info = (args.isNotEmpty && args.first is Map)
            ? Map<String, dynamic>.from(args.first as Map)
            : const <String, dynamic>{};
        unawaited(
          WatchHistoryService.remember(
            groupId: widget.pairId,
            url: (info['url'] ?? '').toString(),
            kind: (info['kind'] ?? '').toString(),
            title: (info['title'] ?? '').toString(),
            thumb: (info['thumb'] ?? '').toString(),
          ),
        );
        return null;
      },
    );
  }

  /// Страница загрузилась (или перезагрузилась — поворот, возврат назад):
  /// она снова ничего не знает про звонок.
  void _onPageLoaded(InAppWebViewController c) {
    if (!mounted) return;
    setState(() => _loading = false);
    _pushVoice();
    if (widget.reels || _native) {
      unawaited(c.evaluateJavascript(source: _insetScript(MediaQuery.paddingOf(context))));
    }
    if (widget.reels && _thumbs.isNotEmpty) _pushThumbs(Map.of(_thumbs));
    if (widget.reels) _reelsChat.pageReady(); // fork
  }
}

/// Нативное окно комнаты: тот же браузер, но своим экраном поверх
/// приложения. Касания идут странице напрямую, мимо Flutter.
class _RoomWindow extends InAppBrowser {
  _RoomWindow({
    required this.onCreated,
    required this.onLoaded,
    required this.onClosed,
    super.initialUserScripts,
  });

  final void Function(InAppWebViewController controller) onCreated;
  final void Function(InAppWebViewController controller) onLoaded;
  final VoidCallback onClosed;

  @override
  void onBrowserCreated() {
    final c = webViewController;
    if (c != null) onCreated(c);
  }

  @override
  void onLoadStop(WebUri? url) {
    final c = webViewController;
    if (c != null) onLoaded(c);
  }

  @override
  void onExit() => onClosed();
}
