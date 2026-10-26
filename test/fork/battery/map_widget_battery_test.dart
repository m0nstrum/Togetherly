import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_map_widget_view.dart';
import 'package:love_app/services/map/map_palette.dart';
import 'package:love_app/widgets/map/pair_map_widget_art.dart';

/// Заряд партнёра на виджете «Где мы» (22.10).
void main() {
  PairMapWidgetArt art({int? battery, bool charging = false}) {
    const cs = ColorScheme.light();
    return PairMapWidgetArt(
      kind: MapWidgetSize.m,
      size: MapWidgetSize.m.size,
      mode: PairMapMode.map,
      palette: MapPalette.of(cs, fill: const Color(0xFFFF7E8B)),
      fill: const Color(0xFFFF7E8B),
      onFill: Colors.white,
      surface: cs.surface,
      onSurface: cs.onSurface,
      onSurfaceVariant: cs.onSurfaceVariant,
      meBg: cs.tertiaryContainer,
      meFg: cs.onTertiaryContainer,
      partnerBg: cs.secondaryContainer,
      partnerFg: cs.onSecondaryContainer,
      me: const Offset(80, 120),
      partner: const Offset(260, 90),
      meInitial: 'С',
      partnerInitial: 'А',
      distance: '3,7 км',
      partnerBattery: battery,
      partnerCharging: charging,
    );
  }

  test('рисуется с зарядом, на зарядке и без него', () async {
    for (final a in [
      art(),
      art(battery: 54),
      art(battery: 5),
      art(battery: 80, charging: true),
    ]) {
      final rec = ui.PictureRecorder();
      a.paint(Canvas(rec));
      final img = await rec.endRecording().toImage(50, 50);
      img.dispose();
    }
  });

  test('сервис виджета передаёт только свежий заряд', () {
    final src = File(
      'lib/services/map/pair_map_widget_service.dart',
    ).readAsStringSync();
    expect(src, contains('ForkBattery.instance.latest(groupId, partnerUid)'));
    expect(src, contains('battery.fresh(DateTime.now())'));
    expect(
      src,
      contains('batteryShown?.level, batteryShown?.charging'),
      reason: 'смена заряда перерисовывает виджет',
    );
  });
}
