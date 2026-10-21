import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../fork/ui/feedback.dart' show ForkFailure; // fork
import '../fork/watch/voice_stage.dart'; // fork
import 'pb_data_service.dart';
import 'watch_channel_service.dart';

/// Состояние голосовой связи в комнате просмотра.
enum VoiceCallState {
  /// Микрофон выключен, связи нет.
  off,

  /// Договариваемся о соединении.
  connecting,

  /// Слышим друг друга.
  live,

  /// Соединение оборвалось, пробуем снова.
  failed,
}

/// Голос между двумя в комнате совместного просмотра.
///
/// Разговор идёт напрямую между устройствами (WebRTC), сервер только знакомит
/// их: предложения и ответы летят тем же каналом `watch:<код>`, что и команды
/// плеера. Ретранслятор (TURN) подключается, когда прямой дороги нет — у
/// российских операторов сплошной CGNAT, и без него связь просто не встаёт.
///
/// Кто звонит первым, решает код комнаты и uid: чтобы двое не начали
/// договариваться одновременно и не перебили друг друга, предложение делает
/// тот, чей uid «больше». Второй ждёт и отвечает.
class WatchVoiceService extends ChangeNotifier {
  WatchVoiceService({required this.channel, required this.me});

  final WatchChannel channel;

  /// Наш uid в комнате.
  final String me;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  MediaStream? _remote;
  final List<RTCIceCandidate> _pending = [];
  String _peer = '';
  bool _polite = false;
  bool _negotiating = false;

  VoiceCallState _state = VoiceCallState.off;
  VoiceCallState get state => _state;

  bool _micOn = false;
  bool _speakerOn = true;

  /// Микрофон включён (нас слышно).
  bool get micOn => _micOn;

  /// Звук включён (мы слышим).
  bool get speakerOn => _speakerOn;

  bool get active => _state != VoiceCallState.off;

  // fork: входящий звонок. Раньше зов при выключенном микрофоне молча
  // пропадал: у звонящего вечное «Звоним…», у партнёра — ничего.
  String _ringing = '';
  Timer? _ringTimer;
  Timer? _helloTimer;
  Timer? _noAnswerTimer;

  /// Кто зовёт поговорить (uid), пока мы не ответили; пусто — никто.
  String get ringingFrom => _ringing;

  // fork (UX L2–L7): стадия и причина сбоя — экран показывает их словами.
  VoiceStage _stage = VoiceStage.idle;
  VoiceProblem? _problem;
  VoiceStage get stage => _stage;
  VoiceProblem? get problem => _problem;
  DateTime? get liveSince => _liveSince;
  Timer? _connectTimer;
  bool _restarted = false;

  /// Сколько ждать соединения после ответа партнёра.
  static const Duration connectFor = Duration(seconds: 30);

  void _setStage(VoiceStage s, [VoiceProblem? p]) {
    _stage = s;
    _problem = p;
    if (s != VoiceStage.connecting && s != VoiceStage.reconnecting) {
      _connectTimer?.cancel();
      _connectTimer = null;
    }
    notifyListeners();
  }

  /// Партнёр откликнулся: ждём соединения, но не вечно.
  void _awaitConnection() {
    if (_stage == VoiceStage.live) return;
    _setStage(VoiceStage.connecting);
    _connectTimer?.cancel();
    _connectTimer = Timer(connectFor, _connectionTimedOut);
  }

  Future<void> _connectionTimedOut() async {
    if (_stage == VoiceStage.live || _state == VoiceCallState.off) return;
    if (await _tryIceRestart()) return;
    await _fail(VoiceProblem.noRoute);
  }

  /// Один раз пробуем заново найти путь (ICE restart) — его делает тот, кто
  /// делает предложения.
  Future<bool> _tryIceRestart() async {
    if (_restarted || _polite || _pc == null || _peer.isEmpty) return false;
    _restarted = true;
    _setStage(VoiceStage.reconnecting);
    _connectTimer = Timer(connectFor, _connectionTimedOut);
    try {
      final offer = await _pc!.createOffer({'iceRestart': true});
      await _pc!.setLocalDescription(offer);
      await channel.send('voice-offer', extra: {'uid': me, 'sdp': offer.sdp});
      return true;
    } catch (e) {
      debugPrint('WatchVoice: ICE restart не вышел: $e');
      return false;
    }
  }

  /// Разорвать и показать причину.
  Future<void> _fail(VoiceProblem p) async {
    await stop();
    _set(VoiceCallState.failed);
    _setStage(VoiceStage.failed, p);
  }

  @visibleForTesting
  void debugStage(VoiceStage s, [VoiceProblem? p]) => _setStage(s, p);

  /// Убрать плашку «не вышло».
  void dismissFailure() {
    if (_state == VoiceCallState.failed) _set(VoiceCallState.off);
    _setStage(VoiceStage.idle);
  }

  /// Звонок ушёл без ответа или партнёр отказался — экран говорит об этом.
  void Function(bool declined)? onUnanswered;

  /// Сколько звать партнёра, прежде чем сдаться.
  static const Duration ringFor = Duration(seconds: 45);

  void _setRinging(String uid) {
    _ringTimer?.cancel();
    _ringing = uid;
    if (uid.isNotEmpty) {
      _ringTimer = Timer(ringFor, () => _setRinging(''));
    }
    notifyListeners();
  }

  /// Не отвечать: звонящему уходит отказ, и он кладёт трубку.
  Future<void> decline() async {
    if (_ringing.isEmpty) return;
    _setRinging('');
    try {
      await channel.send('voice-decline', extra: {'uid': me});
    } catch (_) {/* канал мог закрыться */}
  }

  void _stopCalling() {
    _helloTimer?.cancel();
    _helloTimer = null;
    _noAnswerTimer?.cancel();
    _noAnswerTimer = null;
  }

  /// Разговор кончился: сколько говорили и с кем. Экран кладёт запись в чат
  /// пары (`call_record.dart`).
  void Function(Duration talked, String peer)? onCallEnded;

  DateTime? _liveSince;
  String _talkPeer = '';

  void _set(VoiceCallState s) {
    if (_state == s) return;
    _state = s;
    // Время разговора считается от первого «на связи» до отбоя или обрыва.
    // Временная потеря связи (connecting) разговор не прерывает.
    if (s == VoiceCallState.live && _liveSince == null) {
      _liveSince = DateTime.now();
      _talkPeer = _peer;
    } else if ((s == VoiceCallState.off || s == VoiceCallState.failed) && _liveSince != null) {
      final talked = DateTime.now().difference(_liveSince!);
      _liveSince = null;
      onCallEnded?.call(talked, _talkPeer);
    }
    notifyListeners();
  }

  /// Включить микрофон и позвать собеседника.
  Future<void> start() async {
    // fork (UX L2): после «не вышло» звонок можно начать заново — раньше
    // кнопка в этом состоянии молчала, а «положить трубку» была скрыта.
    if (_state == VoiceCallState.failed) await stop();
    if (_state != VoiceCallState.off) return;
    _restarted = false;
    _set(VoiceCallState.connecting);
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      _micOn = true;
      await _ensurePeer();
      // Зовём собеседника: он поднимет свою сторону и ответит.
      final answering = _ringing.isNotEmpty; // fork
      _setRinging(''); // fork
      _setStage(answering ? VoiceStage.connecting : VoiceStage.calling); // fork
      // fork (UX L5): зов не ушёл — сразу говорим почему, а не ждём 45 с.
      if (!await channel.send('voice-hello', extra: {'uid': me})) {
        await _fail(channel.lastFailure == ForkFailure.noKey
            ? VoiceProblem.noKey
            : VoiceProblem.network);
        return;
      }
      if (answering) _awaitConnection(); // fork
      // fork: зов повторяется, пока партнёр не ответит (он мог зайти в
      // комнату позже), и снимается через [ringFor].
      _stopCalling();
      if (!answering) {
        _helloTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (_peer.isNotEmpty || _state != VoiceCallState.connecting) {
            _stopCalling();
            return;
          }
          unawaited(channel.send('voice-hello', extra: {'uid': me}));
        });
        _noAnswerTimer = Timer(ringFor, () async {
          if (_peer.isNotEmpty || _state != VoiceCallState.connecting) return;
          await _fail(VoiceProblem.noAnswer); // fork
          onUnanswered?.call(false);
        });
      }
      notifyListeners();
    } catch (e) {
      debugPrint('WatchVoice.start failed: $e');
      await _fail(VoiceProblem.noMic); // fork: отказ в микрофоне
    }
  }

  /// Выключить микрофон и разорвать связь.
  Future<void> stop() async {
    _stopCalling(); // fork
    _negotiating = false;
    _pending.clear();
    try {
      await channel.send('voice-bye', extra: {'uid': me});
    } catch (_) {/* канал мог уже закрыться */}
    await _local?.dispose();
    _local = null;
    await _remote?.dispose();
    _remote = null;
    await _pc?.close();
    _pc = null;
    _peer = '';
    _micOn = false;
    _set(VoiceCallState.off);
    _setStage(VoiceStage.idle); // fork
  }

  /// Заглушить или вернуть свой микрофон, не разрывая связь.
  void toggleMic() {
    final track = _local?.getAudioTracks().firstOrNull;
    if (track == null) return;
    _micOn = !_micOn;
    track.enabled = _micOn;
    notifyListeners();
  }

  /// Заглушить или вернуть звук собеседника.
  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    for (final t in _remote?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = _speakerOn;
    }
    notifyListeners();
  }

  /// Разбор сообщений комнаты. Возвращает true, если сообщение наше и экрану
  /// его показывать не нужно.
  Future<bool> handleMessage(Map<String, dynamic> msg) async {
    final type = (msg['t'] ?? '').toString();
    if (!type.startsWith('voice-')) return false;
    final from = (msg['from'] ?? msg['uid'] ?? '').toString();

    switch (type) {
      case 'voice-hello':
        // Нас зовут. Если микрофон уже включён — отвечаем предложением, если
        // нет, сообщение просто игнорируем: навязывать разговор нельзя.
        // fork: но показываем входящий — ответить или отклонить.
        if (_state == VoiceCallState.off) {
          if (from.isNotEmpty && from != me) _setRinging(from);
          return true;
        }
        final fresh = _peer != from; // fork
        _peer = from;
        _polite = me.compareTo(from) < 0;
        _awaitConnection(); // fork (UX L4)
        if (!_polite) {
          await _offer();
        } else if (fresh) {
          // fork: предложение делает партнёр — зовём его в ответ, иначе он
          // ждал бы нашего следующего зова.
          await channel.send('voice-hello', extra: {'uid': me});
        }
        break;
      case 'voice-offer':
        if (_state == VoiceCallState.off) return true;
        _peer = from;
        _polite = me.compareTo(from) < 0;
        if (_stage != VoiceStage.live && _stage != VoiceStage.reconnecting) {
          _awaitConnection(); // fork (UX L4)
        }
        await _ensurePeer();
        await _pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp']?.toString(), 'offer'));
        await _drainPending();
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await channel.send('voice-answer',
            extra: {'uid': me, 'sdp': answer.sdp});
        break;
      case 'voice-answer':
        if (_pc == null) return true;
        await _pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp']?.toString(), 'answer'));
        await _drainPending();
        break;
      case 'voice-ice':
        final c = RTCIceCandidate(
          msg['candidate']?.toString(),
          msg['sdpMid']?.toString(),
          (msg['sdpMLineIndex'] as num?)?.toInt(),
        );
        // Кандидат мог приехать раньше описания — тогда держим его до тех пор,
        // пока соединению будет куда его положить.
        if (_pc == null || (await _pc!.getRemoteDescription()) == null) {
          _pending.add(c);
        } else {
          await _pc!.addCandidate(c);
        }
        break;
      case 'voice-bye':
        if (from == _ringing) _setRinging(''); // fork: передумал звонить
        if (from == _peer) await stop();
        break;
      case 'voice-decline': // fork
        if (_state == VoiceCallState.connecting && _peer.isEmpty) {
          await _fail(VoiceProblem.declined);
          onUnanswered?.call(true);
        }
        break;
    }
    return true;
  }

  Future<void> _ensurePeer() async {
    if (_pc != null) return;
    final ice = await PbDataService().iceServers();
    _pc = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await _pc!.addTrack(track, _local!);
    }

    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      channel.send('voice-ice', extra: {
        'uid': me,
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remote = event.streams.first;
      for (final t in _remote!.getAudioTracks()) {
        t.enabled = _speakerOn;
      }
      _set(VoiceCallState.live);
      _setStage(VoiceStage.live); // fork
    };
    _pc!.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _set(VoiceCallState.live);
          _restarted = false; // fork
          _setStage(VoiceStage.live); // fork
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          // fork (UX L2): сначала один ICE restart, потом — причина.
          unawaited(() async {
            if (!await _tryIceRestart()) await _fail(VoiceProblem.noRoute);
          }());
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _set(VoiceCallState.connecting);
          // fork (UX L12): посреди разговора — «восстанавливаем», а не «звоним».
          _setStage(VoiceStage.reconnecting);
          _connectTimer?.cancel();
          _connectTimer = Timer(connectFor, _connectionTimedOut);
          break;
        default:
          break;
      }
    };
  }

  Future<void> _offer() async {
    if (_negotiating) return;
    _negotiating = true;
    try {
      await _ensurePeer();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
      await _pc!.setLocalDescription(offer);
      await channel.send('voice-offer', extra: {'uid': me, 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('WatchVoice._offer failed: $e');
      _set(VoiceCallState.failed);
    } finally {
      _negotiating = false;
    }
  }

  Future<void> _drainPending() async {
    if (_pc == null) return;
    for (final c in _pending) {
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        debugPrint('WatchVoice: кандидат не лёг: $e');
      }
    }
    _pending.clear();
  }

  @override
  void dispose() {
    _ringTimer?.cancel(); // fork
    _connectTimer?.cancel(); // fork
    unawaited(stop());
    super.dispose();
  }
}
