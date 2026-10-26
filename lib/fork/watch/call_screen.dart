/// Звонок на весь экран — касание по плашке звонка открывает его, как в
/// Telegram (просьба владельца 22.10). Плашка остаётся свёрнутым видом:
/// «свернуть» или «назад» возвращает к ней, разговор идёт дальше.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/feedback.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/watch_voice_service.dart';
import 'voice_stage.dart';

class ForkCallScreen extends StatefulWidget {
  const ForkCallScreen({
    super.key,
    required this.voice,
    required this.partnerName,
    required this.onRetry,
  });

  final WatchVoiceService voice;
  final String partnerName;
  final Future<void> Function() onRetry;

  /// Экран открыт — плашка не дублирует его поверх.
  static final ValueNotifier<bool> visible = ValueNotifier(false);

  /// Открыть поверх всего через [navigator]. Уже открыт — ничего.
  static Future<void> open(
    NavigatorState navigator, {
    required WatchVoiceService voice,
    required String partnerName,
    required Future<void> Function() onRetry,
  }) async {
    if (visible.value) return;
    visible.value = true;
    try {
      await navigator.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, _, _) => ForkCallScreen(
            voice: voice,
            partnerName: partnerName,
            onRetry: onRetry,
          ),
          transitionsBuilder: (_, a, _, child) => SlideTransition(
            position: Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
          settings: const RouteSettings(name: '/fork_call'),
        ),
      );
    } finally {
      visible.value = false;
    }
  }

  @override
  State<ForkCallScreen> createState() => _ForkCallScreenState();
}

class _ForkCallScreenState extends State<ForkCallScreen> {
  Timer? _tick;
  bool _closing = false;

  /// «Позвонить ещё»: стадия на миг станет idle — экран не закрываем.
  bool _retrying = false;

  WatchVoiceService get _v => widget.voice;

  @override
  void initState() {
    super.initState();
    _v.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _v.stage == VoiceStage.live) setState(() {});
    });
  }

  @override
  void dispose() {
    _v.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_v.stage != VoiceStage.idle) _retrying = false;
    // Разговор кончился (положили трубку) — экран больше не нужен.
    if (_v.stage == VoiceStage.idle && !_closing && !_retrying) {
      _closing = true;
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stage = _v.stage;
    final since = _v.liveSince;
    final name = widget.partnerName.isEmpty
        ? ruEn('Партнёр', 'Partner')
        : widget.partnerName;
    final status = voiceStageText(
      stage,
      _v.problem,
      name: widget.partnerName,
      talked: since == null ? null : DateTime.now().difference(since),
    );
    final failed = stage == VoiceStage.failed;
    final live = stage == VoiceStage.live;
    const fg = Colors.white;
    return Scaffold(
      backgroundColor: const Color(0xFF14161C),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A2F3D), Color(0xFF14161C)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: ruEn('Свернуть', 'Minimize'),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: fg,
                    size: 32,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(flex: 2),
              CircleAvatar(
                radius: 56,
                backgroundColor: Colors.white24,
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: fg,
                    fontSize: 44,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name,
                style: const TextStyle(
                  color: fg,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: failed ? const Color(0xFFFFB4AB) : Colors.white70,
                    fontSize: 16,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              if (failed)
                _failedActions()
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundButton(
                      icon: _v.micOn
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      label: _v.micOn
                          ? ruEn('Микрофон', 'Mic')
                          : ruEn('Без звука', 'Muted'),
                      active: !_v.micOn,
                      onTap: _v.toggleMic,
                    ),
                    _RoundButton(
                      icon: Icons.call_end_rounded,
                      label: live
                          ? ruEn('Положить', 'Hang up')
                          : ruEn('Отменить', 'Cancel'),
                      danger: true,
                      onTap: () => unawaited(_v.stop()),
                    ),
                    _RoundButton(
                      icon: _v.speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.hearing_rounded,
                      label: ruEn('Динамик', 'Speaker'),
                      active: _v.speakerOn,
                      onTap: _v.routing
                          ? null
                          : () async {
                              if (!await _v.toggleSpeaker() &&
                                  context.mounted) {
                                ForkNotice.failure(
                                  context,
                                  ForkFailure.unknown,
                                  what: ruEn(
                                    'Не удалось переключить динамик',
                                    'Could not switch the speaker',
                                  ),
                                );
                              }
                            },
                    ),
                  ],
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _failedActions() {
    final p = _v.problem;
    final retry = p != VoiceProblem.noMic && p != VoiceProblem.noKey;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: Icons.close_rounded,
          label: ruEn('Закрыть', 'Close'),
          // Стадия станет idle — экран закроется сам.
          onTap: _v.dismissFailure,
        ),
        if (retry)
          _RoundButton(
            icon: Icons.call_rounded,
            label: ruEn('Позвонить ещё', 'Call again'),
            positive: true,
            onTap: () {
              _retrying = true;
              _v.dismissFailure();
              unawaited(widget.onRetry());
            },
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.positive = false,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool positive;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFE5484D)
        : positive
        ? const Color(0xFF30A46C)
        : active
        ? Colors.white
        : Colors.white24;
    final fg = active && !danger && !positive ? Colors.black87 : Colors.white;
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      selected: active,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Opacity(
              opacity: onTap == null ? .4 : 1,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: fg, size: 30),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
