/// Входящий звонок в комнате «Смотрим вместе» и в ленте вдвоём.
///
/// Звонок поднимает приложение (`WatchVoiceService`), кнопки — на странице.
/// Зов при выключенном микрофоне раньше пропадал молча; теперь карточка
/// поверх страницы: ответить или отклонить. Отвечает экран — у него проверка
/// разрешения на микрофон.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/watch_voice_service.dart';

class ForkIncomingCall extends StatefulWidget {
  const ForkIncomingCall({
    super.key,
    required this.voice,
    required this.onAnswer,
  });

  final WatchVoiceService? voice;
  final Future<void> Function() onAnswer;

  @override
  State<ForkIncomingCall> createState() => _ForkIncomingCallState();
}

class _ForkIncomingCallState extends State<ForkIncomingCall> {
  Timer? _buzz;

  @override
  void initState() {
    super.initState();
    widget.voice?.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(ForkIncomingCall old) {
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
    _buzz?.cancel();
    super.dispose();
  }

  bool get _ringing {
    final v = widget.voice;
    return v != null && v.ringingFrom.isNotEmpty && !v.active;
  }

  void _changed() {
    if (_ringing) {
      if (_buzz == null) {
        unawaited(HapticFeedback.heavyImpact());
        _buzz = Timer.periodic(const Duration(milliseconds: 1600), (_) {
          unawaited(HapticFeedback.heavyImpact());
        });
      }
    } else {
      _buzz?.cancel();
      _buzz = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: !_ringing
              ? const SizedBox.shrink()
              : Padding(
                  key: const ValueKey('ring'),
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                  child: Material(
                    color: cs.surfaceContainerHighest,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                      child: Row(
                        children: [
                          Icon(Icons.call_rounded, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              ruEn(
                                'Партнёр зовёт поговорить',
                                'Your partner wants to talk',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: ruEn('Отклонить', 'Decline'),
                            onPressed: () => unawaited(widget.voice?.decline()),
                            icon: Icon(Icons.call_end_rounded, color: cs.error),
                          ),
                          const SizedBox(width: 4),
                          FilledButton.icon(
                            onPressed: () => unawaited(widget.onAnswer()),
                            icon: const Icon(Icons.call_rounded, size: 18),
                            label: Text(ruEn('Ответить', 'Answer')),
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
