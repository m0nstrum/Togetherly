import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../identity.dart';

/// Launchers can add widgets manually even when pin requests are unavailable.
class ForkManualWidgetHint extends StatelessWidget {
  const ForkManualWidgetHint({super.key});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(Icons.info_outline_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(width: 8),
    Expanded(child: Text(ruEn(
      'Удерживайте пустое место на рабочем столе → Виджеты → ${ForkIdentity.appName}. Выберите виджет и перетащите его на экран.',
      'Touch and hold an empty area on your home screen → Widgets → ${ForkIdentity.appName}. Choose a widget and drag it onto the screen.'),
      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
  ]);
}
