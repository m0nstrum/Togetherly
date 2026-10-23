/// App-wide privacy cover, including dialogs and incoming deep links.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../../widgets/settings_scaffold.dart';
import 'app_lock.dart';

bool get _supported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
String get _reason => ruEn('Разблокировать Tethered', 'Unlock Tethered');
String _problem(ForkLockProblem value) => switch (value) {
  ForkLockProblem.deviceNotSecured => ruEn(
    'Сначала задайте PIN или пароль в настройках защиты телефона.',
    'First set a PIN or password in your phone’s security settings.',
  ),
  ForkLockProblem.unavailable => ruEn(
    'Не удалось проверить защиту. Повторите попытку.',
    'Could not check device security. Please try again.',
  ),
};

class ForkAppLockGate extends StatefulWidget {
  const ForkAppLockGate({super.key, required this.child, this.controller});
  final Widget child;
  final ForkAppLock? controller;
  @override
  State<ForkAppLockGate> createState() => _ForkAppLockGateState();
}

class _ForkAppLockGateState extends State<ForkAppLockGate>
    with WidgetsBindingObserver {
  late final lock = widget.controller ?? ForkAppLock.instance;
  bool get active => widget.controller != null || _supported;
  @override
  void initState() {
    super.initState();
    if (!active) return;
    WidgetsBinding.instance.addObserver(this);
    lock.addListener(_changed);
    unawaited(lock.load());
  }

  void _changed() {
    if (lock.blocked) FocusManager.instance.primaryFocus?.unfocus();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        lock.inactive();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        lock.background();
      case AppLifecycleState.resumed:
        lock.resumed();
    }
  }

  @override
  void dispose() {
    if (active) {
      WidgetsBinding.instance.removeObserver(this);
      lock.removeListener(_changed);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!active) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: lock.blocked,
          child: Offstage(offstage: lock.blocked, child: widget.child),
        ),
        if (lock.blocked)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        ruEn('Tethered заблокирован', 'Tethered is locked'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      if (lock.problem != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _problem(lock.problem!),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (lock.busy || (!lock.ready && lock.problem == null))
                        const CircularProgressIndicator()
                      else
                        FilledButton.icon(
                          onPressed: () =>
                              lock.ready ? lock.unlock(_reason) : lock.load(),
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: Text(
                            lock.ready
                                ? ruEn('Разблокировать', 'Unlock')
                                : ruEn('Повторить', 'Retry'),
                          ),
                        ),
                      if (lock.problem == ForkLockProblem.deviceNotSecured)
                        TextButton(
                          onPressed: lock.openSettings,
                          child: Text(
                            ruEn('Защита телефона', 'Phone security'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ForkAppLockSettings extends StatefulWidget {
  const ForkAppLockSettings({super.key, this.controller});
  final ForkAppLock? controller;
  @override
  State<ForkAppLockSettings> createState() => _ForkAppLockSettingsState();
}

class _ForkAppLockSettingsState extends State<ForkAppLockSettings> {
  late final lock = widget.controller ?? ForkAppLock.instance;
  @override
  void initState() {
    super.initState();
    if (_supported || widget.controller != null) unawaited(lock.load());
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported && widget.controller == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: lock,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRow(
            icon: Icons.lock_rounded,
            title: ruEn('Замок приложения', 'App lock'),
            subtitle: ruEn(
              'Отпечаток или PIN телефона при входе и после фона. Превью в «Недавних» скрыто.',
              'Fingerprint or device PIN on launch and after backgrounding. Recents preview is hidden.',
            ),
            trailing: Switch(
              value: lock.enabled,
              onChanged: lock.ready && !lock.busy
                  ? (value) => lock.setEnabled(value, _reason)
                  : null,
            ),
            onTap: lock.ready && !lock.busy
                ? () => lock.setEnabled(!lock.enabled, _reason)
                : null,
          ),
          if (lock.problem != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_problem(lock.problem!)),
                  if (!lock.ready)
                    TextButton(
                      onPressed: lock.load,
                      child: Text(ruEn('Повторить', 'Retry')),
                    ),
                  if (lock.problem == ForkLockProblem.deviceNotSecured)
                    TextButton(
                      onPressed: lock.openSettings,
                      child: Text(ruEn('Защита телефона', 'Phone security')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
