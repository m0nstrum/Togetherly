import 'package:flutter/material.dart';

import '../dict_strings.dart' show ruEn;
import '../theme/profile_theme.dart';

/// Экран Togetherly+ апстрима. В Tethered покупать нечего — экран говорит,
/// что всё уже открыто.
class PlusScreen extends StatelessWidget {
  const PlusScreen({super.key, required this.scheme});

  final ColorScheme scheme;

  // T6: в Tethered всё открыто всем — витрины с ценой нет. Если какой-то вход
  // на экран всё же сработает, человек увидит это, а не покупку.
  @override
  Widget build(BuildContext context) => _AllOpen(scheme: scheme);
}

class _AllOpen extends StatelessWidget {
  const _AllOpen({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final cs = scheme;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(backgroundColor: cs.surface),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_open_rounded, size: 56, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  ruEn('Всё уже открыто', 'Everything is already open'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  ruEn(
                    'В Tethered нет платных функций — пользуйтесь всем.',
                    'Tethered has no paid features — enjoy everything.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
