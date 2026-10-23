import 'package:flutter/material.dart';

/// Navigator's overlay is above the settings/chat Theme; carry it across.
MaterialPageRoute<T> forkE2ERoute<T>(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return MaterialPageRoute<T>(
    builder: (_) => Theme(data: theme, child: child),
  );
}
