/// Крашрепорты форка: свой Bugsink, только с согласия, без PII
/// (docs/history/PLAN.md, решение 6).
///
/// - Без `SENTRY_DSN` в сборке отправки нет вовсе.
/// - Без согласия SDK стартует с пустым DSN: выключены и Dart-, и нативные
///   краши. Согласие спрашивается один раз после первого кадра и меняется
///   переключателем в настройках.
/// - Отзыв согласия действует сразу: [beforeSend] выбрасывает всё, а SDK
///   закрывается. Включение — со следующего запуска.
/// - `user`, запрос, breadcrumbs с текстом и данными, свои контексты не
///   уходят; в сообщениях вырезаются токены и похожие на координаты числа.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_service.dart';
import '../widgets/settings_scaffold.dart';
import 'config/endpoints.dart';

abstract final class ForkCrashReports {
  static const String prefsKey = 'fork_crash_reports_consent';

  /// Согласие в этом запуске. null — человека ещё не спрашивали.
  static final ValueNotifier<bool?> consent = ValueNotifier<bool?>(null);

  /// Есть ли куда слать: DSN задан в сборке.
  static bool get configured => Endpoints.current.sentryDsn.isNotEmpty;

  /// Было ли согласие на момент старта SDK (DSN ставится только тогда).
  static bool _enabledAtStart = false;

  /// Читает сохранённое согласие. Звать до `SentryFlutter.init`.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      consent.value = prefs.getBool(prefsKey);
    } catch (_) {
      consent.value = null;
    }
  }

  static Future<void> setConsent(bool value) async {
    consent.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {} // тихо: согласие в памяти уже сменено
    if (!value && _enabledAtStart) {
      _enabledAtStart = false;
      await Sentry.close();
    }
  }

  /// Настройки SDK вместо апстримовских: DSN только при согласии, без PII.
  /// [upstreamFilter] — фильтр шума апстрима (`isCrashNoise`), остаётся.
  static void configure(
    SentryFlutterOptions options, {
    required bool Function(Object throwable) upstreamFilter,
  }) {
    _enabledAtStart = !kDebugMode && configured && consent.value == true;
    options.dsn = _enabledAtStart ? Endpoints.current.sentryDsn : '';
    options.sendDefaultPii = false;
    options.enableAutoSessionTracking = false;
    options.attachScreenshot = false;
    options.beforeSend = (event, hint) {
      final t = event.throwable;
      if (t != null && upstreamFilter(t)) return null;
      return beforeSend(event);
    };
    options.beforeBreadcrumb = (crumb, hint) => scrubBreadcrumb(crumb);
  }

  /// Последний рубеж перед отправкой. Видна тестам.
  @visibleForTesting
  static SentryEvent? beforeSend(SentryEvent event) {
    if (consent.value != true) return null;
    return scrubEvent(event);
  }

  /// Контексты, которые нужны для разбора краша и не описывают человека.
  static const Set<String> _keptContexts = {
    'device',
    'os',
    'app',
    'runtime',
    'culture',
    'flutter_context',
  };

  @visibleForTesting
  static SentryEvent scrubEvent(SentryEvent e) {
    final contexts = Contexts();
    for (final entry in e.contexts.entries) {
      if (_keptContexts.contains(entry.key)) contexts[entry.key] = entry.value;
    }
    e
      ..user = null
      ..request = null
      ..serverName = null
      ..contexts = contexts
      ..extra = null
      ..breadcrumbs = e.breadcrumbs
          ?.map(scrubBreadcrumb)
          .whereType<Breadcrumb>()
          .toList();
    final msg = e.message;
    if (msg != null) {
      e.message = SentryMessage(
        scrubText(msg.formatted),
        template: msg.template == null ? null : scrubText(msg.template!),
      );
    }
    for (final ex in e.exceptions ?? const <SentryException>[]) {
      final v = ex.value;
      if (v != null) ex.value = scrubText(v);
    }
    return e;
  }

  /// Оставляет от breadcrumb только тип, категорию и время: в сообщениях и
  /// данных бывают тексты, адреса с токенами и координаты.
  @visibleForTesting
  static Breadcrumb? scrubBreadcrumb(Breadcrumb? b) {
    if (b == null) return null;
    return Breadcrumb(
      type: b.type,
      category: b.category,
      level: b.level,
      timestamp: b.timestamp,
    );
  }

  static final RegExp _token = RegExp(
    r'((?:token|auth|key|code|password|secret)=)[^&\s"]+',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+');
  static final RegExp _jwt = RegExp(
    r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+',
  );
  static final RegExp _email = RegExp(r'[\w.+\-]+@[\w\-]+\.[\w.\-]+');
  // Число с 4+ знаками после точки — координата или около того.
  static final RegExp _coord = RegExp(r'-?\d{1,3}\.\d{4,}');

  @visibleForTesting
  static String scrubText(String s) => s
      .replaceAllMapped(_token, (m) => '${m[1]}[redacted]')
      .replaceAllMapped(_bearer, (m) => '${m[1]}[redacted]')
      .replaceAll(_jwt, '[jwt]')
      .replaceAll(_email, '[email]')
      .replaceAll(_coord, '[num]');

  /// Спрашивает согласие один раз. Звать после первого кадра.
  static Future<void> askOnceIfNeeded(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (!configured || consent.value != null) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final t = _Strings.of();
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t.askTitle),
        content: Text(t.askBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.no),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.yes),
          ),
        ],
      ),
    );
    await setConsent(agreed ?? false);
  }
}

/// Строка в настройках: переключатель отчётов о сбоях. Без DSN в сборке её нет.
class ForkCrashReportsRow extends StatelessWidget {
  const ForkCrashReportsRow({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ForkCrashReports.configured) return const SizedBox.shrink();
    final t = _Strings.of();
    return ValueListenableBuilder<bool?>(
      valueListenable: ForkCrashReports.consent,
      builder: (context, value, _) => SettingsRow(
        icon: Icons.bug_report_rounded,
        title: t.rowTitle,
        subtitle: t.rowHint,
        trailing: Switch(
          value: value == true,
          onChanged: (v) => ForkCrashReports.setConsent(v),
        ),
        onTap: () => ForkCrashReports.setConsent(value != true),
      ),
    );
  }
}

/// Свои строки форка: в словарь апстрима не лезем (конфликты при мёржах).
class _Strings {
  const _Strings._ru()
    : askTitle = 'Отправлять отчёты о сбоях?',
      askBody =
          'Если приложение упадёт, оно отправит технический отчёт на '
          'сервер вашего инстанса: модель телефона, версию системы и место '
          'ошибки в коде. Без текстов, имён, адресов и координат. Изменить '
          'можно в настройках.',
      yes = 'Отправлять',
      no = 'Не надо',
      rowTitle = 'Отчёты о сбоях',
      rowHint = 'Без личных данных. Включение — после перезапуска';

  const _Strings._en()
    : askTitle = 'Send crash reports?',
      askBody =
          'If the app crashes, it will send a technical report to your '
          'instance\'s server: phone model, OS version and where the error '
          'happened. No texts, names, addresses or locations. You can change '
          'this in settings.',
      yes = 'Send',
      no = 'No thanks',
      rowTitle = 'Crash reports',
      rowHint = 'No personal data. Turning on applies after restart';

  final String askTitle;
  final String askBody;
  final String yes;
  final String no;
  final String rowTitle;
  final String rowHint;

  static _Strings of() {
    final code = LocaleService.instance.language.code.toLowerCase();
    return code == 'ru' || code == 'uk' || code == 'be'
        ? const _Strings._ru()
        : const _Strings._en();
  }
}
