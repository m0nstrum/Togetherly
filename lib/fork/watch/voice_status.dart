/// Плашка звонка поверх комнаты и ленты: что сейчас происходит — зовём,
/// соединяем, на связи, восстанавливаем, не вышло и почему (UX_AUDIT L2–L7,
/// L12). Раньше на всё было одно «Звоним…».
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/watch_voice_service.dart';
import '../ui/feedback.dart';
import 'call_screen.dart';
import 'voice_stage.dart';

class ForkVoiceStatus extends StatefulWidget {
  const ForkVoiceStatus({
    super.key,
    required this.voice,
    required this.onRetry,
    this.partnerName = '',
    this.navigator,
  });

  /// Где открыть звонок на весь экран; null — навигатор над плашкой.
  final NavigatorState? navigator;

  final WatchVoiceService? voice;

  /// «Повторить» после сбоя: экран зовёт заново (с проверкой микрофона).
  final Future<void> Function() onRetry;
  final String partnerName;

  /// Открыта комната просмотра: звонок показывает её шапка, а плашка поверх
  /// окна видео закрывала бы кадр — остаётся только для сбоев.
  static final ValueNotifier<bool> roomOpen = ValueNotifier(false);

  @override
  State<ForkVoiceStatus> createState() => _ForkVoiceStatusState();
}

class _ForkVoiceStatusState extends State<ForkVoiceStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.voice?.addListener(_changed);
    ForkCallScreen.visible.addListener(_changed);
    ForkVoiceStatus.roomOpen.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ForkVoiceStatus old) {
    super.didUpdateWidget(old);
    if (old.voice != widget.voice) {
      old.voice?.removeListener(_changed);
      widget.voice?.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.voice?.removeListener(_changed);
    ForkCallScreen.visible.removeListener(_changed);
    ForkVoiceStatus.roomOpen.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    final live = widget.voice?.stage == VoiceStage.live;
    if (live && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  void _expand(WatchVoiceService v) {
    final nav = widget.navigator ?? Navigator.maybeOf(context, rootNavigator: true);
    if (nav == null) return;
    unawaited(ForkCallScreen.open(
      nav,
      voice: v,
      partnerName: widget.partnerName,
      onRetry: widget.onRetry,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.voice;
    final stage = v?.stage ?? VoiceStage.idle;
    final since = v?.liveSince;
    final text = voiceStageText(
      stage,
      v?.problem,
      name: widget.partnerName,
      talked: since == null ? null : DateTime.now().difference(since),
    );
    final show = v != null &&
        stage != VoiceStage.idle &&
        text.isNotEmpty &&
        !ForkCallScreen.visible.value && // fork: экран звонка открыт — плашка не нужна
        !(ForkVoiceStatus.roomOpen.value && stage != VoiceStage.failed);
    final (tone, label, action) = switch (stage) {
      // Закрыть — крестиком всегда; «Позвонить ещё» — где повтор поможет.
      VoiceStage.failed => (
        ForkStatusTone.error,
        v?.problem == VoiceProblem.noMic || v?.problem == VoiceProblem.noKey
            ? null
            : ruEn('Позвонить ещё', 'Call again'),
        v?.problem == VoiceProblem.noMic || v?.problem == VoiceProblem.noKey
            ? null
            : () {
                v?.dismissFailure();
                unawaited(widget.onRetry());
              },
      ),
      VoiceStage.live => (ForkStatusTone.info, ruEn('Положить', 'Hang up'), () => unawaited(v?.stop())),
      _ => (ForkStatusTone.progress, ruEn('Отменить', 'Cancel'), () => unawaited(v?.stop())),
    };
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: !show
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(stage),
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                  child: ForkStatusBar(
                    text: text,
                    tone: tone,
                    actionLabel: label,
                    onAction: action,
                    // Как в Telegram: касание разворачивает звонок на весь экран.
                    onTap: () => _expand(v),
                    // «Не ответил», «отклонил» и прочие сбои убираются крестиком,
                    // без нового звонка.
                    onClose: stage == VoiceStage.failed
                        ? () => v.dismissFailure()
                        : null,
                  ),
                ),
        ),
      ),
    );
  }
}
