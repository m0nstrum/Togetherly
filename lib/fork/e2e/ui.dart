/// Плашка состояния ключей пары и экран сверки (docs/fork/E2E.md §6.3,
/// решение §12.4: непроверенная пара работает, но плашка кричит).
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/locale_service.dart';
import 'e2e_service.dart';
import 'fork_e2e.dart';
import 'sas.dart';

bool get _ru => const {
  'ru',
  'uk',
  'be',
}.contains(LocaleService.instance.language.code.toLowerCase());

String _t(String ru, String en) => _ru ? ru : en;

/// Плашка над лентой чата. Пусто, когда всё проверено или E2E не запущен.
class ForkE2EBanner extends StatelessWidget {
  const ForkE2EBanner({
    super.key,
    required this.groupId,
    required this.partnerUid,
    required this.partnerName,
  });

  final String groupId;
  final String partnerUid;
  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<E2EService?>(
      valueListenable: ForkE2E.service,
      builder: (context, svc, _) {
        if (svc == null || groupId.isEmpty) return const SizedBox.shrink();
        return ValueListenableBuilder<SasState?>(
          valueListenable: svc.sas,
          builder: (context, sas, _) => ValueListenableBuilder<Map<String, PairE2EStatus>>(
            valueListenable: svc.status,
            builder: (context, all, _) {
              final incoming = sas is SasIncoming && sas.groupId == groupId;
              final (text, danger) = switch (all[groupId]) {
                _ when incoming => (
                  _t(
                    '$partnerName зовёт сверить ключи',
                    '$partnerName wants to verify keys',
                  ),
                  false,
                ),
                PairE2EStatus.unverified => (
                  _t(
                    'Ключи не проверены — сверьте эмодзи',
                    'Keys not verified — compare emoji',
                  ),
                  false,
                ),
                PairE2EStatus.keyChanged => (
                  _t(
                    'Ключ $partnerName сменился. Если не переустанавливали — сверьте эмодзи',
                    '$partnerName\'s key changed. If they didn\'t reinstall, compare emoji',
                  ),
                  true,
                ),
                PairE2EStatus.tampered => (
                  _t(
                    'Ключи не сходятся — возможна подмена сервером. Сверьте эмодзи по звонку',
                    'Keys don\'t match — the server may have swapped them. Compare emoji on a call',
                  ),
                  true,
                ),
                _ => ('', false),
              };
              if (text.isEmpty) return const SizedBox.shrink();
              final scheme = Theme.of(context).colorScheme;
              final bg = danger
                  ? scheme.errorContainer
                  : scheme.tertiaryContainer;
              final fg = danger
                  ? scheme.onErrorContainer
                  : scheme.onTertiaryContainer;
              return Material(
                color: bg,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ForkE2EVerifyScreen(
                        groupId: groupId,
                        partnerUid: partnerUid,
                        partnerName: partnerName,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          danger
                              ? Icons.gpp_bad_rounded
                              : Icons.gpp_maybe_rounded,
                          color: fg,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _t('Сверить', 'Verify'),
                          style: TextStyle(
                            color: fg,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Экран сверки: эмодзи голосом или QR вживую.
class ForkE2EVerifyScreen extends StatefulWidget {
  const ForkE2EVerifyScreen({
    super.key,
    required this.groupId,
    required this.partnerUid,
    required this.partnerName,
  });

  final String groupId;
  final String partnerUid;
  final String partnerName;

  @override
  State<ForkE2EVerifyScreen> createState() => _ForkE2EVerifyScreenState();
}

class _ForkE2EVerifyScreenState extends State<ForkE2EVerifyScreen> {
  bool _qr = false;
  bool _busy = false;

  E2EService? get _svc => ForkE2E.service.value;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Не получилось: $e', 'Failed: $e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final s = _svc?.sas.value;
    // Ушли с экрана посреди сверки — партнёр не должен ждать вечно.
    if (s != null && s is! SasFinished && s is! SasIncoming) _svc?.sasCancel();
    if (s is SasFinished) _svc?.sas.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = _svc;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Сверка ключей', 'Verify keys')),
        actions: [
          TextButton(
            onPressed: () => setState(() => _qr = !_qr),
            child: Text(_qr ? _t('Эмодзи', 'Emoji') : 'QR'),
          ),
        ],
      ),
      body: svc == null
          ? Center(
              child: Text(
                _t('Шифрование ещё не готово', 'Encryption is not ready yet'),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _qr ? _qrView(svc) : _sasView(svc),
              ),
            ),
    );
  }

  Widget _sasView(E2EService svc) {
    return ValueListenableBuilder<SasState?>(
      valueListenable: svc.sas,
      builder: (context, st, _) {
        final name = widget.partnerName;
        final mine = st != null && st.groupId == widget.groupId ? st : null;
        final children = switch (mine) {
          null => [
            _p(
              _t(
                'Созвонитесь с $name и откройте этот экран оба. Нажмите «Начать» — у обоих появятся 7 эмодзи. '
                    'Назовите их друг другу вслух: совпали — ключи настоящие, сервер их не подменил.',
                'Call $name and both open this screen. Tap “Start” — you’ll both see 7 emoji. '
                    'Read them to each other: if they match, your keys are genuine.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => svc.sasStart(widget.groupId, widget.partnerUid),
                    ),
              child: Text(_t('Начать', 'Start')),
            ),
          ],
          SasWaiting() => [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            _p(
              _t(
                'Ждём, пока $name откроет экран сверки…',
                'Waiting for $name to open verification…',
              ),
            ),
          ],
          SasIncoming() => [
            _p(_t('$name зовёт сверить ключи.', '$name wants to verify keys.')),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : () => _run(svc.sasAccept),
              child: Text(_t('Сверить', 'Verify')),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(svc.sasCancel),
              child: Text(_t('Не сейчас', 'Not now')),
            ),
          ],
          SasShowCode(:final code) => [
            _p(
              _t(
                'Назовите эмодзи вслух по очереди:',
                'Read the emoji aloud in turn:',
              ),
            ),
            const SizedBox(height: 16),
            _emoji(code),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => svc.sasConfirm(match: true)),
              child: Text(_t('Совпадают', 'They match')),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => svc.sasConfirm(match: false)),
              child: Text(_t('Не совпадают', 'They don’t match')),
            ),
          ],
          SasFinished(:final match) => [
            Icon(
              match ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
              size: 64,
              color: match ? Colors.green : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            _p(
              match
                  ? _t(
                      'Готово: ключи $name проверены.',
                      'Done: $name’s keys are verified.',
                    )
                  : _t(
                      'Эмодзи не совпали. Возможно, сервер подменил ключи — не пишите ничего важного и попробуйте ещё раз по звонку.',
                      'The emoji didn’t match. The server may have swapped keys — avoid sensitive messages and retry on a call.',
                    ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                svc.sas.value = null;
                if (match) Navigator.of(context).maybePop();
              },
              child: Text(
                match ? _t('Закрыть', 'Close') : _t('Ещё раз', 'Try again'),
              ),
            ),
          ],
        };
        return ListView(children: children);
      },
    );
  }

  Widget _emoji(SasCode code) {
    final lang = _ru ? 'ru' : 'en';
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 16,
      children: [
        for (final e in code.emoji)
          SizedBox(
            width: 84,
            child: Column(
              children: [
                Text(e.symbol, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 4),
                Text(e.name(lang), textAlign: TextAlign.center),
              ],
            ),
          ),
      ],
    );
  }

  Widget _qrView(E2EService svc) {
    final payload = svc.qrPayload(widget.partnerUid);
    if (payload == null) {
      return Center(
        child: _p(
          _t('Ключей партнёра ещё нет', 'Partner keys not available yet'),
        ),
      );
    }
    return ListView(
      children: [
        _p(
          _t(
            'Встретьтесь с ${widget.partnerName}: каждый сканирует QR другого.',
            'Meet ${widget.partnerName}: each scans the other’s QR.',
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ColoredBox(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: payload, size: 220),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(_t('Сканировать QR партнёра', 'Scan partner’s QR')),
          onPressed: _busy
              ? null
              : () async {
                  final scanned = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => const _QrScan()),
                  );
                  if (scanned == null || !mounted) return;
                  final ok = await svc.verifyByQr(
                    widget.groupId,
                    widget.partnerUid,
                    scanned,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? _t('Ключи проверены', 'Keys verified')
                            : _t(
                                'QR не совпал — возможна подмена ключей',
                                'QR mismatch — keys may be swapped',
                              ),
                      ),
                    ),
                  );
                  if (ok) Navigator.of(context).maybePop();
                },
        ),
      ],
    );
  }

  Widget _p(String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge,
    textAlign: TextAlign.center,
  );
}

class _QrScan extends StatefulWidget {
  const _QrScan();

  @override
  State<_QrScan> createState() => _QrScanState();
}

class _QrScanState extends State<_QrScan> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: MobileScanner(
      onDetect: (capture) {
        final v = capture.barcodes.firstOrNull?.rawValue;
        if (_done || v == null || !v.startsWith('tethered-verify:')) return;
        _done = true;
        Navigator.of(context).pop(v);
      },
    ),
  );
}
