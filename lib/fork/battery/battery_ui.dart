/// Заряд партнёра на экранах: значок в шапке чата и строка в профиле.
library;

import 'dart:async';
import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../widgets/common/stable_stream_builder.dart';
import 'battery_share.dart';

/// Значок по уровню: батарейка наполняется, при зарядке — молния.
IconData forkBatteryIcon(ForkBatteryState s) => forkBatteryIconFor(s.level, charging: s.charging);

/// То же по числам — для виджета карты, который рисуется на холсте.
IconData forkBatteryIconFor(int l, {bool charging = false}) {
  if (charging) return Icons.battery_charging_full_rounded;
  if (l >= 95) return Icons.battery_full_rounded;
  if (l >= 80) return Icons.battery_6_bar_rounded;
  if (l >= 65) return Icons.battery_5_bar_rounded;
  if (l >= 50) return Icons.battery_4_bar_rounded;
  if (l >= 35) return Icons.battery_3_bar_rounded;
  if (l >= 20) return Icons.battery_2_bar_rounded;
  if (l >= 8) return Icons.battery_1_bar_rounded;
  return Icons.battery_alert_rounded;
}

/// «заряжается», «скоро сядет», «40 мин назад».
String forkBatteryNote(ForkBatteryState s, DateTime now) {
  final age = now.difference(s.at);
  final parts = <String>[
    if (s.charging) ruEn('заряжается', 'charging') else if (s.low) ruEn('скоро сядет', 'running low'),
    if (age >= const Duration(minutes: 15))
      age.inMinutes < 60
          ? ruEn('${age.inMinutes} мин назад', '${age.inMinutes} min ago')
          : ruEn('${age.inHours} ч назад', '${age.inHours} h ago'),
  ];
  return parts.isEmpty ? ruEn('заряд телефона', 'phone battery') : parts.join(' · ');
}

/// Живой заряд [uid]; пусто, если его нет или он устарел.
class ForkBatteryWatch extends StatefulWidget {
  const ForkBatteryWatch({
    super.key,
    required this.groupId,
    required this.uid,
    required this.builder,
    this.maxAge = const Duration(hours: 6),
    this.states,
    this.now,
  });

  final String groupId;
  final String uid;
  final Widget Function(BuildContext context, ForkBatteryState state) builder;
  final Duration maxAge;
  final Stream<ForkBatteryState?> Function()? states;
  final DateTime Function()? now;

  @override
  State<ForkBatteryWatch> createState() => _ForkBatteryWatchState();
}

class _ForkBatteryWatchState extends State<ForkBatteryWatch> {
  Timer? _expiry;

  @override
  void dispose() { _expiry?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => StableStreamBuilder<ForkBatteryState?>(
        create: widget.states ?? () => ForkBattery.instance.watch(widget.groupId, widget.uid),
        keys: [widget.groupId, widget.uid, widget.states],
        builder: (context, snap) {
          final s = snap.data;
          if (s == null || !s.fresh((widget.now ?? DateTime.now)(), maxAge: widget.maxAge)) {
            _expiry?.cancel(); _expiry = null;
            return const SizedBox.shrink();
          }
          _expiry ??= Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          });
          return widget.builder(context, s);
        },
      );
}

/// Компактно, для шапки чата: значок и процент.
class ForkBatteryBadge extends StatelessWidget {
  const ForkBatteryBadge({super.key, required this.groupId, required this.uid, required this.color, this.states, this.now});

  final String groupId;
  final String uid;
  final Color color;
  final Stream<ForkBatteryState?> Function()? states;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => ForkBatteryWatch(
        groupId: groupId,
        uid: uid,
        maxAge: const Duration(hours: 1),
        states: states, now: now,
        builder: (context, s) {
          final c = s.low ? Theme.of(context).colorScheme.error : color;
          final note = forkBatteryNote(s, (now ?? DateTime.now)());
          return Tooltip(message: note, child: Semantics(
            label: '${ruEn('Заряд телефона ${s.level}%', 'Phone battery ${s.level}%')} · $note',
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RotatedBox(quarterTurns: 1, child: Icon(forkBatteryIcon(s), size: 15, color: c)),
                  const SizedBox(width: 2),
                  Text(
                    '${s.level}%',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
                  ),
                ],
              ),
            ),
          ));
        },
      );
}

/// Переключатель «Показывать партнёру заряд» для настроек.
class ForkBatteryShareSwitch extends StatelessWidget {
  const ForkBatteryShareSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    ForkBattery.instance.ensureLoaded();
    return ValueListenableBuilder<bool>(
        valueListenable: ForkBattery.instance.sharing,
        builder: (context, on, _) => Switch(
          value: on,
          onChanged: (v) => ForkBattery.instance.setSharing(v),
        ),
      );
  }
}
