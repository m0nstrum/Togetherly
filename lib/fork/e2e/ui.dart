/// Плашка состояния ключей пары и экран сверки (docs/fork/E2E.md §6.3,
/// решение §12.4: непроверенная пара работает, но плашка кричит).
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/locale_service.dart';
import 'backup.dart' show BackupMethod;
import '../ui/feedback.dart';
import 'backup_ui.dart';
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
        return ValueListenableBuilder<BackupMethod?>(
          valueListenable: svc.backupMethod,
          builder: (context, backup, _) => ValueListenableBuilder<SasState?>(
          valueListenable: svc.sas,
          builder: (context, sas, _) => ValueListenableBuilder<Map<String, PairE2EStatus>>(
            valueListenable: svc.status,
            builder: (context, all, _) {
              final incoming = sas is SasIncoming && sas.groupId == groupId;
              // Ключи без бэкапа: потеря телефона = потеря переписки, а
              // сказано об этом было только в настройках (UX_AUDIT A2).
              final backupOff = backup == null &&
                  !svc.needsRestore.value &&
                  all[groupId] != PairE2EStatus.needsRestore;
              final (text, danger) = switch (all[groupId]) {
                _ when incoming => (
                  _t(
                    '$partnerName зовёт сверить ключи',
                    '$partnerName wants to verify keys',
                  ),
                  false,
                ),
                PairE2EStatus.needsRestore => (
                  _t(
                    'Восстановите ключи из бэкапа, чтобы читать историю',
                    'Restore your keys from backup to read your history',
                  ),
                  false,
                ),
                PairE2EStatus.unverified => (
                  _t(
                    'Переписка зашифрована. Сверьте 7 эмодзи с $partnerName — так вы убедитесь, что ключи ваши',
                    'Your chat is encrypted. Compare 7 emoji with $partnerName to make sure the keys are yours',
                  ),
                  false,
                ),
                PairE2EStatus.keyChanged => (
                  _t(
                    'Ключ $partnerName сменился — обычно это новый телефон или переустановка. Если не ожидали, сверьте эмодзи',
                    '$partnerName\'s key changed — usually a new phone or a reinstall. If you didn\'t expect it, compare emoji',
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
                PairE2EStatus.waitingPartner => (
                  _t(
                    'Ждём, пока $partnerName войдёт в новую версию: пока нет ключей партнёра, писать нельзя',
                    'Waiting for $partnerName to open the new version: you can’t write until their keys arrive',
                  ),
                  false,
                ),
                PairE2EStatus.waitingKey => (
                  _t(
                    'Договариваемся о ключе пары — сообщения можно будет писать через пару секунд',
                    'Agreeing on the pair key — you’ll be able to write in a moment',
                  ),
                  false,
                ),
                _ when backupOff => (
                  _t(
                    'Ключи без бэкапа: потеряете телефон — потеряете переписку. Включить бэкап',
                    'Keys have no backup: lose your phone, lose your history. Turn on backup',
                  ),
                  false,
                ),
                _ => ('', false),
              };
              if (text.isEmpty) return const SizedBox.shrink();
              final toBackup = backupOff &&
                  !incoming &&
                  (all[groupId] == null || all[groupId] == PairE2EStatus.verified);
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
                      builder: (_) => toBackup
                          ? const ForkE2EBackupScreen()
                          : all[groupId] == PairE2EStatus.needsRestore
                          ? const ForkE2ERestoreScreen()
                          : ForkE2EVerifyScreen(
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
                          toBackup
                              ? _t('Включить', 'Turn on')
                              : all[groupId] == PairE2EStatus.needsRestore
                              ? _t('Восстановить', 'Restore')
                              : _t('Сверить', 'Verify'),
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
        ForkNotice.error(
          context,
          e,
          what: _t('Сверка не прошла', 'Verification failed'),
          retry: () => _run(f),
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
    if (s != null && s is! SasFinished && s is! SasStopped && s is! SasIncoming) {
      _svc?.sasCancel();
    }
    if (s is SasFinished || s is SasStopped) _svc?.sas.value = null;
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
                'Созвонитесь с $name. «Начать» нажимает один из вас — второму придёт «Сверить» '
                    '(в чате или на этом экране). Потом у обоих появятся 7 эмодзи: назовите их вслух. '
                    'Совпали — ключи настоящие, сервер их не подменил. Нажали оба — не страшно, сверка будет одна.',
                'Call $name. One of you taps “Start” — the other gets “Verify” (in the chat or on this screen). '
                    'Then you’ll both see 7 emoji: read them aloud. If they match, your keys are genuine. '
                    'If you both tap Start, that’s fine — there will be one check.',
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
          SasWaiting(:final started) => [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            _p(
              started
                  ? _t(
                      'Ждём, пока $name нажмёт «Сверить» — плашка с приглашением у него в чате. '
                          'Подождём две минуты, потом можно начать заново.',
                      'Waiting for $name to tap “Verify” — the invite banner is in their chat. '
                          'We’ll wait two minutes, then you can start again.',
                    )
                  : _t(
                      'Приняли. Ждём, пока телефон $name откроет эмодзи — обычно пара секунд, '
                          'приложение у него должно быть открыто.',
                      'Accepted. Waiting for $name’s phone to reveal the emoji — usually a couple of '
                          'seconds; their app should be open.',
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _busy ? null : () => _run(svc.sasCancel),
              child: Text(_t('Отменить', 'Cancel')),
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
          SasStopped(:final why) => [
            Icon(
              Icons.info_outline_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            _p(switch (why) {
              SasStopWhy.partnerCancelled => _t(
                '$name отменил сверку. Эмодзи не сравнивали — ничего плохого не случилось.',
                '$name cancelled. The emoji weren’t compared — nothing is wrong.',
              ),
              SasStopWhy.noAnswer => _t(
                'Телефон $name не ответил за две минуты. Пусть откроет приложение — и начните заново.',
                '$name’s phone didn’t answer in two minutes. Ask them to open the app and start again.',
              ),
              SasStopWhy.lost => _t(
                'Сверка потерялась: приложение $name перезапустилось. Начните заново.',
                'The check got lost: $name’s app restarted. Start again.',
              ),
            }),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => svc.sas.value = null,
              child: Text(_t('Начать заново', 'Start again')),
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
                                'Отпечатки не совпали. Если ${widget.partnerName} недавно переустанавливал(а) приложение — '
                                    'пусть заново откроет этот экран и покажет свежий QR. Если нет — возможна подмена ключей.',
                                'Fingerprints don’t match. If ${widget.partnerName} reinstalled the app recently, ask them to reopen '
                                    'this screen and show a fresh QR. If not, the keys may have been swapped.',
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
