import 'package:flutter/material.dart';

/// Keep the name and live status readable without competing for one line.
class ForkChatIdentityLayout extends StatelessWidget {
  const ForkChatIdentityLayout({
    super.key,
    required this.name,
    required this.dot,
    required this.status,
    required this.battery,
  });
  final Widget name;
  final Widget dot;
  final Widget status;
  final Widget battery;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          dot,
          const SizedBox(width: 6),
          Expanded(child: name),
        ],
      ),
      const SizedBox(height: 2),
      LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Expanded(child: status),
            if (box.maxWidth >= 180) battery,
          ],
        ),
      ),
    ],
  );
}
