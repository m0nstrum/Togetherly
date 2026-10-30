import 'package:flutter/material.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MD3 PHOTO LOADER — анимация загрузки фото
// ══════════════════════════════════════════════════════════════════════════════

class MD3PhotoLoader extends StatefulWidget {
  final Color color;
  const MD3PhotoLoader({super.key, required this.color});

  @override
  State<MD3PhotoLoader> createState() => _MD3PhotoLoaderState();
}

class _MD3PhotoLoaderState extends State<MD3PhotoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ring = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Внешнее пульсирующее кольцо
            Transform.scale(
              scale: 1.0 + _pulse.value * 0.12,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.08 + _pulse.value * 0.07),
                ),
              ),
            ),
            // Среднее кольцо — чуть в противофазе
            Transform.scale(
              scale: 1.0 + (1 - _ring.value) * 0.08,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.06 + (1 - _ring.value) * 0.06),
                ),
              ),
            ),
            // MD3 индикатор загрузки
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: color,
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                backgroundColor: color.withOpacity(0.12),
              ),
            ),
            // Иконка фото в центре
            Opacity(
              opacity: 0.25 + _pulse.value * 0.35,
              child: Icon(Icons.image_rounded, size: 18, color: color),
            ),
          ],
        );
      },
    );
  }
}
