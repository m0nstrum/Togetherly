// fork (D10): «чистый экран» в лентах вдвоём, как в TikTok.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';

/// Удержание двумя пальцами: пока держишь — [onHold] `true`, отпустил все
/// пальцы — `false`.
///
/// Ловит касания [Listener]-ом: он не входит в арену жестов, поэтому браузер
/// ленты под ним (там свайп, касание и двойное касание) получает те же
/// касания, что и раньше. Поднятый первым палец интерфейс не возвращает —
/// иначе он мигал бы, когда пальцы отрываются не одновременно.
class ForkTwoFingerHold extends StatefulWidget {
  const ForkTwoFingerHold({
    super.key,
    required this.onHold,
    required this.child,
  });

  final ValueChanged<bool> onHold;
  final Widget child;

  @override
  State<ForkTwoFingerHold> createState() => _ForkTwoFingerHoldState();
}

class _ForkTwoFingerHoldState extends State<ForkTwoFingerHold> {
  final Set<int> _down = <int>{};
  bool _held = false;

  void _onDown(PointerDownEvent e) {
    // Мышь и стилус — не пальцы: колесо и клик мыши в эмуляторе не прячут
    // интерфейс.
    if (e.kind != PointerDeviceKind.touch) return;
    _down.add(e.pointer);
    if (!_held && _down.length >= 2) _set(true);
  }

  void _onUp(PointerEvent e) {
    if (!_down.remove(e.pointer)) return;
    if (_held && _down.isEmpty) _set(false);
  }

  void _set(bool held) {
    _held = held;
    widget.onHold(held);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onDown,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: widget.child,
  );
}
