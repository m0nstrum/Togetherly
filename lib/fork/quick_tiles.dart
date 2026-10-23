/// Optional Android QS entries. The OS component state is authoritative.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dict_strings.dart' show ruEn;
import '../widgets/settings_scaffold.dart';

class ForkQuickTilesSettings extends StatefulWidget {
  const ForkQuickTilesSettings({super.key});
  @override
  State<ForkQuickTilesSettings> createState() => _ForkQuickTilesSettingsState();
}

class _ForkQuickTilesSettingsState extends State<ForkQuickTilesSettings> {
  static const _channel = MethodChannel('tethered/quick_tiles');
  bool _enabled = false, _busy = true, _available = true, _failed = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  void initState() {
    super.initState();
    if (_android) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final enabled = await _channel.invokeMethod<bool>('getEnabled');
      if (mounted) {
        setState(() {
          _available = enabled != null;
          _enabled = enabled ?? false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await _channel.invokeMethod<void>('setEnabled', value);
      if (mounted) setState(() => _enabled = value);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_android || !_available) return const SizedBox.shrink();
    final title = ruEn('Плитки в шторке', 'Quick settings tiles');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          icon: Icons.dashboard_customize_rounded,
          title: title,
          subtitle: _busy
              ? ruEn('Проверяем настройки…', 'Checking settings…')
              : ruEn(
                  'Открывайте «Скучаю» и «Прикосновение» из шторки. После включения добавьте плитки через её кнопку «Изменить».',
                  'Open Miss you and Touch from quick settings. After enabling, add the tiles using its Edit button.',
                ),
          trailing: Semantics(
            label: title,
            child: Switch(
              value: _enabled,
              onChanged: _busy || _failed ? null : _set,
            ),
          ),
          onTap: _busy || _failed ? null : () => _set(!_enabled),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruEn(
                    'Не удалось изменить плитки. Проверьте состояние ещё раз.',
                    'Could not update tiles. Check their state again.',
                  ),
                ),
                TextButton(
                  onPressed: _load,
                  child: Text(ruEn('Повторить', 'Retry')),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
