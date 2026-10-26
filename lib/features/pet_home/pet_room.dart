import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pet_home_model.dart';

const petCream = Color(0xFFF7EDDB);
const petInk = Color(0xFF563F2E);
const petSage = Color(0xFF939A77);
const petClay = Color(0xFFCD8265);

/// Each object is a separate transparent sprite. Normalised anchors keep the
/// room stable across screen sizes; the user's art is an independent layer.
class PetRoom extends StatefulWidget {
  const PetRoom({
    super.key,
    required this.home,
    required this.pet,
    this.speech,
    this.action,
    this.animationKey = 0,
    this.onPet,
    this.petLabel = 'Pet',
    this.speechLabel = 'Pet says',
  });
  final PetHome home;
  final Widget pet;
  final String? speech;
  final PetCare? action;
  final int animationKey;
  final VoidCallback? onPet;
  final String petLabel, speechLabel;
  @override
  State<PetRoom> createState() => _PetRoomState();
}

class _PetRoomState extends State<PetRoom> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didUpdateWidget(PetRoom old) {
    super.didUpdateWidget(old);
    if (old.animationKey != widget.animationKey &&
        !MediaQuery.disableAnimationsOf(context)) {
      _animation.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _animation.reset();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, c) {
        final size = c.maxWidth;
        Widget sprite(String id, double x, double y, double width) =>
            Positioned(
              left: (x - width / 2) * size,
              top: (y - width / 2) * size,
              width: width * size,
              height: width * size,
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/pet_home/$id.webp',
                  fit: BoxFit.contain,
                ),
              ),
            );
        final layers = <PetSlot, (double, double, double)>{
          PetSlot.picture: (.25, .34, .16),
          PetSlot.seat: (.32, .52, .51),
          PetSlot.bed: (.77, .62, .33),
          PetSlot.plant: (.86, .47, .29),
          PetSlot.decor: (.13, .62, .25),
        };
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/pet_home/room.webp',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (widget.home.equipped[PetSlot.rug] case final String rug)
              sprite(rug, .49, .77, .65),
            for (final e in layers.entries)
              if (widget.home.equipped[e.key] case final String id)
                sprite(id, e.value.$1, e.value.$2, e.value.$3),
            sprite('bowl', .80, .82, .18),
            Positioned(
              left: .29 * size,
              top: .56 * size,
              width: .34 * size,
              height: .30 * size,
              child: Semantics(
                label: widget.petLabel,
                button: true,
                child: GestureDetector(
                  onTap: widget.onPet,
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedBuilder(
                    animation: _animation,
                    child: widget.pet,
                    builder: (context, child) {
                      final t = _animation.value;
                      final wave = math.sin(t * math.pi * 6) * (1 - t);
                      final movement = switch (widget.action) {
                        PetCare.play => Offset(
                          wave * size * .035,
                          -wave.abs() * size * .04,
                        ),
                        PetCare.feed => Offset(0, wave * size * .012),
                        _ => Offset.zero,
                      };
                      return Transform.translate(
                        offset: movement,
                        child: Transform.rotate(
                          angle: widget.action == PetCare.pet ? wave * .07 : 0,
                          child: Transform.scale(
                            scale:
                                1 +
                                (widget.action == PetCare.wash
                                    ? wave.abs() * .035
                                    : 0),
                            child: child,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (widget.action != null)
              Positioned(
                left: .34 * size,
                top: .57 * size,
                width: .28 * size,
                height: .28 * size,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _animation,
                    builder: (context, _) {
                      final t = _animation.value;
                      final symbols = switch (widget.action) {
                        PetCare.wash => ['◯', '○', '◯', '○'],
                        PetCare.pet => ['♥', '♡', '♥'],
                        PetCare.feed => ['✦', '✧', '✦'],
                        _ => ['♪', '✦', '♫'],
                      };
                      return Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Stack(
                          children: [
                            for (var i = 0; i < symbols.length; i++)
                              Positioned(
                                left: (i / (symbols.length - 1)) * .20 * size,
                                top:
                                    (.10 - t * .12 + math.sin(i * 2) * .025) *
                                    size,
                                child: Text(
                                  symbols[i],
                                  style: TextStyle(
                                    fontSize: size * .065,
                                    color: widget.action == PetCare.wash
                                        ? const Color(0xFF679FB2)
                                        : petClay,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (widget.speech case final String speech)
              Positioned(
                left: .15 * size,
                right: .15 * size,
                bottom: .43 * size,
                child: IgnorePointer(
                  child: Semantics(
                    liveRegion: true,
                    label: '${widget.speechLabel}: $speech',
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8EB),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: petInk.withValues(alpha: .16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: petInk.withValues(alpha: .08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  speech,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: petInk,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Icon(
                                  switch (widget.action) {
                                    PetCare.wash => Icons.bubble_chart_outlined,
                                    PetCare.play => Icons.music_note_rounded,
                                    PetCare.feed => Icons.auto_awesome_rounded,
                                    _ => Icons.favorite_rounded,
                                  },
                                  color: petClay,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          CustomPaint(
                            size: const Size(18, 9),
                            painter: _BubbleTail(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _BubbleTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * .4, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFFFF8EB));
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) => false;
}
