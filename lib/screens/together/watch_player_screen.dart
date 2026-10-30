import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:video_player/video_player.dart';

import '../../fork/ui/feedback.dart'; // fork (UX V1, V9, V11)
import '../../dict_strings.dart' show ruEn; // fork (UX)
import '../../services/locale_service.dart';
import '../../services/pb_media_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/watch_sync.dart';
import '../../services/screen_awake.dart';
import '../../services/watch_voice_service.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_history_service.dart';
import '../../widgets/common/m3_loading.dart';
import '../../widgets/unfold/unfold_route.dart';
import '../../widgets/watch/watch_voice_bar.dart';

/// Нативный просмотр своего видео вдвоём.
///
/// Кадр рисует сам Flutter, поэтому управление мгновенное, а не через
/// встроенный браузер. Комната — тот же канал Centrifugo, что у сайта: пауза,
/// перемотка и подтяжка времени понятны и вкладке в браузере.
class WatchPlayerScreen extends StatefulWidget {
  final String room;
  final String pairId;

  /// Ссылка на файл: прямая или наша `pb://media/...` (её резолвим сами).
  final String url;
  final String title;

  const WatchPlayerScreen({
    super.key,
    required this.room,
    required this.pairId,
    required this.url,
    this.title = '',
  });

  @override
  State<WatchPlayerScreen> createState() => _WatchPlayerScreenState();
}

class _WatchPlayerScreenState extends State<WatchPlayerScreen>
    with SingleTickerProviderStateMixin {
  /// Расхождение, после которого догоняем партнёра. Меньше — дёргается на
  /// каждой мелочи, больше — заметно расходятся реплики в фильме.
  static const Duration _drift = Duration(milliseconds: 1500);

  VideoPlayerController? _video;
  WatchChannel? _room;

  /// Голосовая связь в комнате: микрофон, звук, соединение между двумя.
  WatchVoiceService? _voice;
  Timer? _heartbeat;

  /// fork (B10): «я здесь» для страницы комнаты. Плеер сидит в канале
  /// подключением приложения, а его присутствие страница не считает, —
  /// без этого партнёр видел «не в комнате», пока здесь стоит пауза.
  Timer? _here;
  Timer? _hideControls;

  bool _ready = false;
  bool _applying = false;

  /// Кто второй в комнате. Приходит с первым же сообщением партнёра и решает,
  /// кто задаёт время: отметку шлёт ровно один, иначе двое догоняют друг
  /// друга и видео дёргается назад каждые несколько секунд.
  String _peer = '';
  String _me = '';
  bool _controlsVisible = true;
  String _error = '';
  bool _failedSend = false; // fork (UX V11): команда не дошла до партнёра
  DateTime _lastSendWarn = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    // fork (UX V9): повтор после сбоя начинает с чистого экрана.
    if (_error.isNotEmpty) setState(() => _error = '');
    final playable = await PbMediaService.instance.resolvePlayable(widget.url);
    final controller = VideoPlayerController.networkUrl(Uri.parse(playable));
    try {
      await controller.initialize();
    } catch (e) {
      // fork (UX V9): причина словами; экран даёт «Повторить» и «Закрыть».
      await controller.dispose();
      if (!mounted) return;
      final f = ForkFailure.of(e);
      setState(
        () => _error = f == ForkFailure.unknown
            ? ruEn(
                'Ролик не открылся. Возможно, формат не поддерживается или файл удалён.',
                'Couldn’t open the video. The format may be unsupported or the file was removed.',
              )
            : f.text,
      );
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }

    final me = PocketBaseService().userId ?? 'app';
    _me = me;
    final room = WatchChannel(widget.room, me);
    // Аудит B-4: пока ждём комнату, экран могут закрыть, а connect — бросить.
    // До setState ниже контроллер ничей: dispose экрана о нём не знает,
    // поэтому освобождаем здесь. Канал при отказе закрывает сам join.
    var adopted = false;
    try {
      final joined = await room.join(_onRoomMessage, alive: () => mounted);
      if (!joined) return;
      adopted = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ForkFailure.of(e).text);
      return;
    } finally {
      if (!adopted) await controller.dispose();
    }
    controller.addListener(_onPlayerTick);

    // Голос живёт в том же канале, что и команды плеера: отдельный сигналинг
    // ради двух человек — лишняя сущность, а комната у них уже общая.
    final voice = WatchVoiceService(channel: room, me: me);
    voice.addListener(_onVoiceChanged);

    setState(() {
      _video = controller;
      _room = room;
      _voice = voice;
      _ready = true;
    });

    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      final v = _video;
      if (v == null || !v.value.isPlaying) return;
      // Отметку времени шлёт только ведущий. Обоюдный heartbeat и был
      // причиной рывков: каждый прыгал назад на дорогу чужого сообщения.
      if (!leadsSync(me: _me, peer: _peer)) return;
      room.send(
        'sync',
        at: v.value.position.inMilliseconds / 1000,
        extra: {'playing': true},
      );
    });
    _here = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(room.send('here'));
    });
    _scheduleHide();
  }

  // ── разговор с комнатой ────────────────────────────────────────────────────

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  /// Включить или выключить разговор. Микрофон спрашивает сам WebRTC; отказ
  /// оставляет плеер как был, без разговоров.
  Future<void> _toggleVoice() async {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active) {
      await voice.stop();
    } else {
      await voice.start();
      if (mounted && voice.state == VoiceCallState.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleService.current.voiceNoPermission)),
        );
      }
    }
  }

  void _onRoomMessage(Map<String, dynamic> data) {
    // Сообщения голосовой связи (`voice-*`) разбирает сам сервис: плееру они
    // ничего не говорят.
    final voice = _voice;
    if (voice != null && (data['t'] ?? '').toString().startsWith('voice-')) {
      unawaited(voice.handleMessage(data));
      return;
    }
    final v = _video;
    if (v == null) return;
    final at = ((data['at'] ?? 0) as num).toDouble();
    final from = (data['from'] ?? '').toString();
    if (from.isNotEmpty && from != _me && from != _peer) _peer = from;

    switch (data['t']) {
      case 'play':
        _apply(play: true, at: at);
        break;
      case 'pause':
        _apply(play: false, at: at);
        break;
      case 'sync':
        // Ведущий свои же отметки не слушает: он и есть источник времени.
        if (leadsSync(me: _me, peer: _peer)) break;
        final target = catchUpTarget(
          mine: v.value.position,
          theirs: Duration(milliseconds: (at * 1000).round()),
          playing: data['playing'] == true,
          drift: _drift,
        );
        if (target != null) {
          _apply(
            play: data['playing'] == true,
            at: target.inMilliseconds / 1000,
          );
        }
        break;
      case 'hello':
        // Пришедшему позже рассказываем, что смотрим и с какой секунды.
        _room?.send(
          'state',
          at: v.value.position.inMilliseconds / 1000,
          extra: {
            'to': data['from'],
            'url': widget.url,
            'playing': v.value.isPlaying,
          },
        );
        break;
    }
  }

  /// fork (UX V11): команда партнёру; не дошла — говорим, не чаще раза в 8 с.
  Future<void> _cmd(String type, {double at = 0}) async {
    final room = _room;
    if (room == null) return;
    final ok = await room.send(type, at: at);
    if (!mounted) return;
    if (ok) {
      if (_failedSend) setState(() => _failedSend = false);
      return;
    }
    if (!_failedSend) setState(() => _failedSend = true);
    final now = DateTime.now();
    if (now.difference(_lastSendWarn) > const Duration(seconds: 8)) {
      _lastSendWarn = now;
      ForkNotice.failure(
        context,
        room.lastFailure ?? ForkFailure.network,
        what: ruEn(
          'Партнёр не получил команду',
          'Your partner didn’t get that',
        ),
      );
    }
  }

  Future<void> _apply({required bool play, required double at}) async {
    final v = _video;
    if (v == null) return;
    _applying = true;
    final target = Duration(milliseconds: (at * 1000).round());
    if ((v.value.position - target).abs() > _drift) await v.seekTo(target);
    if (play) {
      await v.play();
    } else {
      await v.pause();
    }
    Timer(const Duration(milliseconds: 400), () => _applying = false);
  }

  void _onPlayerTick() {
    // Пока ролик играет, экран не гаснет: плагин плеера сам его не держит
    // (жалоба 12.10.2026). На паузе отпускаем — пусть телефон засыпает.
    ScreenAwake.sync(this, playing: _video?.value.isPlaying ?? false);
    if (mounted) setState(() {});
  }

  /// Кнопки нажимает человек — значит команда уходит партнёру.
  Future<void> _togglePlay() async {
    final v = _video;
    if (v == null) return;
    final at = v.value.position.inMilliseconds / 1000;
    if (v.value.isPlaying) {
      await v.pause();
      if (!_applying) await _cmd('pause', at: at);
    } else {
      await v.play();
      if (!_applying) await _cmd('play', at: at);
    }
    _scheduleHide();
  }

  Future<void> _seekTo(Duration position) async {
    final v = _video;
    if (v == null) return;
    await v.seekTo(position);
    if (_applying) return;
    await _cmd(
      v.value.isPlaying ? 'play' : 'pause',
      at: position.inMilliseconds / 1000,
    );
  }

  // ── показ и скрытие кнопок ─────────────────────────────────────────────────

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 3), () {
      if (mounted && (_video?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _tapScreen() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  void dispose() {
    ScreenAwake.release(this);
    _heartbeat?.cancel();
    _here?.cancel();
    _hideControls?.cancel();
    _voice?.removeListener(_onVoiceChanged);
    _voice?.dispose();
    _video?.removeListener(_onPlayerTick);
    final seconds = (_video?.value.position.inSeconds ?? 0);
    if (seconds > 5) {
      // Куда досмотрели — пригодится в «Недавнем».
      unawaited(
        WatchHistoryService.remember(
          groupId: widget.pairId,
          url: widget.url,
          kind: 'memory',
          title: widget.title,
          seconds: seconds,
        ),
      );
    }
    _video?.dispose();
    final room = _room;
    if (room != null) {
      // fork (B10): ушли из плеера — страница партнёра убирает нас сразу.
      unawaited(() async {
        await room.send('bye');
        await room.dispose();
      }());
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;

    // Плеер чёрный: окно перехода под ним тоже должно быть чёрным.
    UnfoldTint.claim(context, Colors.black);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error.isNotEmpty
            ? Center(
                // fork (UX V9): белый текст на чёрном и кнопки «Повторить / Закрыть».
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.white70,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        children: [
                          FilledButton(
                            onPressed: _open,
                            child: Text(ruEn('Повторить', 'Retry')),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: Text(ruEn('Закрыть', 'Close')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : !_ready || v == null
            ? const Center(child: M3Loading(color: Colors.white))
            : GestureDetector(
                onTap: _tapScreen,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: v.value.aspectRatio,
                        child: VideoPlayer(v),
                      ),
                    ),
                    // fork (UX V1, V11): партнёр ещё не в ролике / связь рвётся.
                    if (_peer.isEmpty || _failedSend)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 56,
                        child: ForkStatusBar(
                          tone: ForkStatusTone.warning,
                          text: _failedSend
                              ? ruEn(
                                  'Нет связи: партнёр может не получать ваши команды.',
                                  'No connection: your partner may not get your commands.',
                                )
                              : ruEn(
                                  'Этот ролик из приложения у партнёра не включается сам. Попросите открыть его в «Смотрим» — тогда вы будете смотреть синхронно.',
                                  'This video doesn’t start on your partner’s phone by itself. Ask them to open it in “Watch” to sync up.',
                                ),
                        ),
                      ),
                    _Controls(
                      visible: _controlsVisible,
                      playing: v.value.isPlaying,
                      position: v.value.position,
                      duration: v.value.duration,
                      title: widget.title,
                      onPlayPause: _togglePlay,
                      onSeek: _seekTo,
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
      ),
      // Голос стоит под кадром и не исчезает вместе со слоем управления: тот
      // прячется через несколько секунд, и вместе с ним пропадала кнопка
      // звонка. Говорить хотят и не глядя в экран, поэтому полоса постоянная.
      bottomNavigationBar: _voice == null
          ? null
          : WatchVoiceBar(
              state: _voice!.state,
              micOn: _voice!.micOn,
              speakerOn: _voice!.speakerOn,
              onCallToggle: _toggleVoice,
              onMicToggle: () => _voice?.toggleMic(),
              onSpeakerToggle: () => _voice?.toggleSpeaker(),
            ),
    );
  }
}

/// Слой управления: появляется и уходит плавно, кнопки — крупные и круглые,
/// как велит язык форм Material 3.
class _Controls extends StatelessWidget {
  final bool visible;
  final bool playing;
  final Duration position;
  final Duration duration;
  final String title;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onClose;

  const _Controls({
    required this.visible,
    required this.playing,
    required this.position,
    required this.duration,
    required this.title,
    required this.onPlayPause,
    required this.onSeek,
    required this.onClose,
  });

  static String _stamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.72),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: ruEn('Закрыть', 'Close'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(color: Colors.white),
                    ),
                  ),
                  // Кнопок разговора здесь больше нет: они уехали в полосу
                  // под кадром. Слой управления сам прячется через несколько
                  // секунд, и вместе с ним пропадала возможность позвонить —
                  // а поговорить люди хотят и не глядя в экран.
                  const SizedBox(width: 12),
                ],
              ),
              const Spacer(),
              // Кнопка «играть» подрастает и меняет значок с переливом —
              // движение здесь важнее любой другой мелочи в кадре.
              AnimatedScale(
                scale: visible ? 1 : 0.85,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    onTap: onPlayPause,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(playing),
                          color: cs.onPrimary,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: cs.primary,
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 18,
                        ),
                      ),
                      child: Slider(
                        value: position.inMilliseconds
                            .clamp(0, total)
                            .toDouble(),
                        max: total.toDouble(),
                        onChanged: (v) =>
                            onSeek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _stamp(position),
                          style: text.labelMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _stamp(duration),
                          style: text.labelMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
