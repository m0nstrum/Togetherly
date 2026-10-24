import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../../models/chat_msg.dart';

/// Track observed new messages even when they leave the bounded live window.
class ForkChatBelowTracker {
  int _seenThrough = -1;
  final Map<String, int> _below = {};
  int get count => _below.length;

  void markSeen(int timestamp) {
    if (timestamp > _seenThrough) _seenThrough = timestamp;
    _below.clear();
  }

  int update(
    Iterable<ChatMsg> messages, {
    required String myUid,
    required bool atBottom,
  }) {
    var newest = 0;
    for (final m in messages) {
      if (m.ts > newest) newest = m.ts;
    }
    if (_seenThrough < 0 && newest == 0) return 0;
    if (_seenThrough < 0 || atBottom) {
      markSeen(newest);
      return 0;
    }
    for (final m in messages) {
      if (m.deleted) {
        _below.remove(m.id);
        continue;
      }
      if (m.uid != myUid && m.ts > _seenThrough) _below[m.id] = m.ts;
    }
    return count;
  }
}

class ForkChatScrollDown extends StatelessWidget {
  const ForkChatScrollDown({
    super.key,
    required this.count,
    required this.onTap,
    required this.surface,
    required this.ink,
  });
  final int count;
  final VoidCallback onTap;
  final Color surface;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final label = count > 0
        ? ruEn('Новые сообщения ниже: $count', 'New messages below: $count')
        : ruEn('К последнему сообщению', 'Go to latest message');
    return Semantics(
      label: label,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: surface,
            foregroundColor: ink,
            minimumSize: const Size(48, 48),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 26),
        ),
      ),
    );
  }
}
