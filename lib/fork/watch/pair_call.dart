/// Голосовой звонок пары — один на всё приложение (UX_AUDIT C0, T4, L6).
///
/// Раньше звонок жил внутри экрана комнаты: позвонить из чата было нельзя,
/// зов партнёра слышал только тот, кто сидел в комнате, а выход из комнаты
/// обрывал разговор. Теперь канал комнаты пары (`watch:<код>`) поднимается
/// при входе в пару и слушает зов всегда, пока приложение открыто; звонят
/// из чата, комнаты и ленты одним и тем же [WatchVoiceService], а входящий
/// звонок и плашка состояния висят поверх любого экрана.
library;

import 'picture_in_picture.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../main.dart' show LoveApp;
import '../../models/call_record.dart';
import '../../services/chat_service.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/watch_channel_service.dart';
import '../../services/watch_room_service.dart';
import '../../services/watch_voice_service.dart';
import 'incoming_call.dart';
import 'voice_stage.dart';
import 'voice_status.dart';

class ForkPairCall {
  ForkPairCall._();
  static final ForkPairCall instance = ForkPairCall._();

  /// Текущий звонок пары; null — пара не привязана или канал не поднялся.
  final ValueNotifier<WatchVoiceService?> voice = ValueNotifier(null);

  /// Как зовут партнёра — для плашки («Зовём Аню…»).
  String partnerName = '';

  String _group = '';
  String _room = '';
  WatchChannel? _channel;
  Future<WatchVoiceService?>? _binding;
  OverlayEntry? _overlay;

  /// Поднять канал комнаты пары [groupId] (или комнаты [room], если код уже
  /// известен) и слушать зов. Повторный вызов для той же пары ничего не
  /// делает.
  Future<WatchVoiceService?> bind(String groupId, {String room = ''}) {
    final current = voice.value;
    if (current != null &&
        ((room.isNotEmpty && room == _room) ||
            (groupId.isNotEmpty && groupId == _group))) {
      return Future.value(current);
    }
    return _binding ??= _bind(groupId, room).whenComplete(() => _binding = null);
  }

  Future<WatchVoiceService?> _bind(String groupId, String room) async {
    try {
      final code = room.isNotEmpty ? room : await WatchRoomService.roomCode(groupId);
      final me = PocketBaseService().userId ?? '';
      if (code.isEmpty || me.isEmpty) return null;
      await unbind();
      final ch = WatchChannel(code, me);
      final v = WatchVoiceService(channel: ch, me: me);
      await ch.connect((data) {
        if ('${data['t'] ?? ''}'.startsWith('voice-')) {
          unawaited(v.handleMessage(data));
        }
      });
      v.onCallEnded = (talked, peer) => _record(groupId, me, talked, peer);
      v.onCalling = () => unawaited(_ring(groupId));
      _group = groupId;
      _room = code;
      _channel = ch;
      voice.value = v;
      _showOverlay();
      return v;
    } catch (e) {
      debugPrint('ForkPairCall: канал пары не поднялся: $e');
      return null;
    }
  }

  /// Позвонить партнёру. Канал не поднялся — плашка скажет почему.
  Future<void> call(String groupId) async {
    final v = await bind(groupId);
    if (v == null) {
      final ctx = LoveApp.rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(voiceStageText(VoiceStage.failed, VoiceProblem.noChannel)),
          ),
        );
      }
      return;
    }
    await v.start();
  }

  /// Выход из аккаунта или из пары: разговор кончается, канал закрывается.
  Future<void> unbind() async {
    final v = voice.value;
    voice.value = null;
    _overlay?.remove();
    _overlay = null;
    if (v != null) {
      await v.stop();
      v.dispose();
    }
    final ch = _channel;
    _channel = null;
    _group = '';
    _room = '';
    if (ch != null) await ch.dispose();
  }

  /// Зов ушёл в канал комнаты — его слышит только открытое приложение.
  /// Сервер будит телефон партнёра (сокет фонового сервиса и пуш FCM без
  /// содержимого): тот видит «Партнёр звонит», открывает приложение и
  /// получает зов, который звонящий повторяет 45 с (UX_AUDIT L6).
  Future<void> _ring(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      await PocketBaseService().pb.send(
        '/api/fork/ring',
        method: 'POST',
        body: {'group_id': groupId},
      );
    } catch (e) {
      // Партнёр в приложении всё равно услышит зов; закрытое — нет.
      debugPrint('ForkPairCall: партнёра не разбудили: $e');
    }
  }

  /// Разговор кончился — запись «Звонок · 4:12» в чат пары. Пишет один из
  /// двоих (`writesCallRecord`), иначе в истории было бы по две записи.
  void _record(String groupId, String me, Duration talked, String peer) {
    if (talked < kMinCallRecord || groupId.isEmpty) return;
    if (!writesCallRecord(me: me, peer: peer)) return;
    final ms = talked.inMilliseconds;
    unawaited(
      ChatService.instance.send(
        groupId: groupId,
        senderName: PocketBaseService().userName,
        text: callRecordText(LocaleService.current.chatCallTitle, ms),
        callMs: ms,
      ),
    );
  }

  /// Входящий и плашка звонка — поверх любого экрана. Пустые места
  /// пропускают касания насквозь.
  void _showOverlay() {
    if (_overlay != null) return;
    final overlay = LoveApp.rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Навигатор ещё не построен (холодный старт) — попробуем после кадра.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (voice.value != null) _showOverlay();
      });
      return;
    }
    _overlay = OverlayEntry(
      builder: (_) => ForkPipHideChrome(child: ValueListenableBuilder<WatchVoiceService?>(
        valueListenable: voice,
        builder: (_, v, _) => Stack(
          children: [
            ForkIncomingCall(voice: v, onAnswer: () async => v?.start()),
            ForkVoiceStatus(
              voice: v,
              partnerName: partnerName,
              onRetry: () async => v?.start(),
              navigator: LoveApp.rootNavigatorKey.currentState,
            ),
          ],
        ),
      )),
    );
    overlay.insert(_overlay!);
  }
}
