/// Привязка второго устройства по QR (docs/E2E.md §5.3, BACKLOG T3):
/// новый телефон показывает QR и ждёт, старый — сканирует и отдаёт ключи.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../dict_strings.dart' show ruEn;
import '../../widgets/qr/qr_viewfinder.dart';
import '../../widgets/settings_scaffold.dart';
import '../secure_screen.dart';
import '../ui/feedback.dart';
import 'crypto.dart' show E2EVerifyError;
import 'device_link.dart';
import 'e2e_service.dart';
import 'fork_e2e.dart';
import 'themed_route.dart';

/// Новый телефон: QR для старого и ожидание ключей.
class ForkE2ELinkShowScreen extends StatefulWidget {
  const ForkE2ELinkShowScreen({super.key, this.service, this.poll});

  /// Для тестов; по умолчанию — [ForkE2E.service].
  final E2EService? service;

  /// Как часто спрашивать сервер.
  final Duration? poll;

  @override
  State<ForkE2ELinkShowScreen> createState() => _ForkE2ELinkShowScreenState();
}

class _ForkE2ELinkShowScreenState extends State<ForkE2ELinkShowScreen> {
  E2EService get _svc => widget.service ?? ForkE2E.service.value!;
  String? _qr;
  String? _error;
  bool _expired = false;
  bool _done = false;
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_done) unawaited(_svc.linkCancel());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _qr = null;
      _error = null;
      _expired = false;
    });
    try {
      final qr = await _svc.linkStart();
      if (!mounted) return;
      setState(() => _qr = qr.encode());
      _timer?.cancel();
      _timer = Timer.periodic(
        widget.poll ?? const Duration(seconds: 2),
        (_) => _tick(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = ForkFailure.of(e).text);
    }
  }

  Future<void> _tick() async {
    if (_polling || _done) return;
    _polling = true;
    try {
      if (await _svc.linkPoll()) {
        _done = true;
        _timer?.cancel();
        if (!mounted) return;
        ForkNotice.info(
          context,
          ruEn(
            'Телефон привязан — история и ключи на месте',
            'Phone linked — your history and keys are here',
          ),
        );
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on E2ELinkExpired {
      _timer?.cancel();
      if (mounted) setState(() => _expired = true);
    } on E2EVerifyError {
      _timer?.cancel();
      if (mounted) {
        setState(
          () => _error = ruEn(
            'Ключи пришли не с вашего телефона — привязка остановлена. Начните заново.',
            'The keys didn’t come from your phone — linking stopped. Start again.',
          ),
        );
      }
    } catch (_) {
      // сеть: следующий тик повторит
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) => ForkSecureScreen(builder: _body);

  Widget _body(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ruEn('Привязать к другому телефону', 'Link from another phone'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              ruEn(
                'На телефоне, где вы уже вошли: Настройки → Шифрование → «Привязать новое устройство» — и наведите камеру на этот код.',
                'On the phone where you’re already signed in: Settings → Encryption → “Link a new device”, then point the camera at this code.',
              ),
              style: text.bodyLarge,
            ),
            const SizedBox(height: 24),
            if (_error != null || _expired) ...[
              Text(
                _error ?? ruEn('Код устарел.', 'The code has expired.'),
                style: text.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _start,
                child: Text(ruEn('Показать новый код', 'Show a new code')),
              ),
            ] else if (_qr == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    key: ValueKey<String>(_qr!),
                    data: _qr!,
                    size: 240,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      ruEn(
                        'Ждём другой телефон…',
                        'Waiting for the other phone…',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                ruEn(
                  'Не показывайте этот код другим: по нему ваш телефон получает ключи шифрования.',
                  'Don’t show this code to anyone else: it lets your phone receive your encryption keys.',
                ),
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Старый телефон: сканер QR нового и подтверждение.
class ForkE2ELinkScanScreen extends StatefulWidget {
  const ForkE2ELinkScanScreen({super.key});

  @override
  State<ForkE2ELinkScanScreen> createState() => _ForkE2ELinkScanScreenState();
}

class _ForkE2ELinkScanScreenState extends State<ForkE2ELinkScanScreen> {
  bool _handled = false;

  Future<void> _onScanned(String raw) async {
    if (_handled) return;
    final qr = LinkQr.parse(raw);
    if (qr == null) return;
    _handled = true;
    final svc = ForkE2E.service.value;
    if (svc == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ruEn('Привязать это устройство?', 'Link this device?')),
        content: Text(
          ruEn(
            'Новый телефон получит ваши ключи шифрования и сможет читать всю переписку. Привязывайте только свой телефон, который держите в руках.',
            'The new phone will get your encryption keys and read all your history. Only link your own phone that’s in your hands.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ruEn('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ruEn('Привязать', 'Link')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      _handled = false;
      return;
    }
    try {
      await svc.linkApprove(qr);
      if (!mounted) return;
      ForkNotice.info(
        context,
        ruEn(
          'Ключи отправлены — новый телефон готов через пару секунд',
          'Keys sent — the new phone will be ready in a moment',
        ),
      );
      Navigator.of(context).pop();
    } on E2EVerifyError {
      if (!mounted) return;
      ForkNotice.info(
        context,
        ruEn(
          'Код не от вашего аккаунта или подменён — ключи не отправлены',
          'The code isn’t from your account or was tampered with — keys not sent',
        ),
      );
      Navigator.of(context).pop();
    } on E2ELinkExpired {
      if (!mounted) return;
      ForkNotice.info(
        context,
        ruEn(
          'Код устарел — покажите на новом телефоне новый',
          'The code expired — show a new one on the new phone',
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      _handled = false;
      if (mounted) ForkNotice.failure(context, ForkFailure.of(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      title: Text(ruEn('Код с нового телефона', 'Code from the new phone')),
    ),
    body: LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final side = size.shortestSide * kQrWindowFraction;
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              scanWindow: Rect.fromCenter(
                center: Offset(size.width / 2, size.height / 2),
                width: side,
                height: side,
              ),
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    ruEn(
                      'Камера недоступна: разрешите доступ в настройках телефона.',
                      'Camera unavailable: allow access in phone settings.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              onDetect: (capture) {
                for (final b in capture.barcodes) {
                  final raw = b.rawValue;
                  if (raw != null) unawaited(_onScanned(raw));
                }
              },
            ),
            const QrViewfinder(),
          ],
        );
      },
    ),
  );
}

/// Строка настроек на старом телефоне: «Привязать новое устройство».
class ForkE2ELinkRow extends StatelessWidget {
  const ForkE2ELinkRow({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<E2EService?>(
    valueListenable: ForkE2E.service,
    builder: (context, svc, _) => svc == null
        ? const SizedBox.shrink()
        : ValueListenableBuilder<bool>(
            valueListenable: svc.needsRestore,
            builder: (context, restore, _) => restore
                ? const SizedBox.shrink()
                : SettingsRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: ruEn(
                      'Привязать новое устройство',
                      'Link a new device',
                    ),
                    subtitle: ruEn(
                      'Второй телефон получит ключи по QR — без фразы и пароля',
                      'Your second phone gets the keys by QR — no phrase or password',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ForkE2ELinkScanScreen(),
                      ),
                    ),
                  ),
          ),
  );
}

/// Маршрут к экрану QR на новом телефоне — в теме экранов шифрования.
Route<void> forkE2ELinkShowRoute(BuildContext context) =>
    forkE2ERoute<void>(context, const ForkE2ELinkShowScreen());
