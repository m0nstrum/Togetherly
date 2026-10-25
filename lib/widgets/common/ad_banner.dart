// fork: рекламы в форке нет (docs/history/PLAN.md, решение 1; TOUCHPOINTS.md).
// Заглушка с API апстрима: баннер не занимает места. При мёрже апстрима этот
// файл берём свой.
import 'package:flutter/widgets.dart';

/// Рекламный баннер. В форке пустое место нулевого размера.
class AdBanner extends StatelessWidget {
  final double height;
  final bool framed;
  final String label;
  final String slot;

  const AdBanner({
    super.key,
    this.height = 50,
    this.framed = false,
    this.label = '',
    this.slot = '',
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
