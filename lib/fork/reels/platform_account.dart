/// Вход в свой аккаунт площадки для «Лент вдвоём».
///
/// Ленту держит скрытый браузер (`ReelsFeed`), а куки браузера у приложения
/// общие: вошёл здесь — и скрытая лента идёт уже по своим рекомендациям.
/// Вход — на странице самой площадки в видимом окне: приложение не встраивает
/// туда скриптов и куки не читает, пароль уходит площадке напрямую. Выйти —
/// стереть куки её доменов.
///
/// Shorts не предлагаем: Google не пускает вход во встроенных браузерах
/// («disallowed_useragent»).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/reels_source.dart';
import '../../services/reels/reels_proxy.dart';

/// Что нужно знать о входе на площадку.
class PlatformAccount {
  const PlatformAccount({
    required this.login,
    required this.domains,
    this.session,
  });

  /// Страница входа.
  final String login;

  /// Сайты, чьи куки стираются при выходе.
  final List<String> domains;

  /// Кука сессии: по ней видно, что вошли. null — не знаем, статус не
  /// показываем.
  final ({String url, String name})? session;

  static PlatformAccount? of(ReelsSource s) => switch (s) {
    ReelsSource.tiktok => const PlatformAccount(
      login: 'https://www.tiktok.com/login',
      domains: ['https://www.tiktok.com', 'https://tiktok.com'],
      session: (url: 'https://www.tiktok.com', name: 'sessionid'),
    ),
    ReelsSource.vkClips => const PlatformAccount(
      login: 'https://m.vk.com/login',
      domains: [
        'https://m.vk.com',
        'https://vk.com',
        'https://login.vk.com',
        'https://id.vk.com',
      ],
      session: (url: 'https://m.vk.com', name: 'remixsid'),
    ),
    ReelsSource.dzen => const PlatformAccount(
      login:
          'https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fdzen.ru%2Fshorts',
      domains: [
        'https://dzen.ru',
        'https://passport.yandex.ru',
        'https://yandex.ru',
      ],
      session: (url: 'https://passport.yandex.ru', name: 'Session_id'),
    ),
    ReelsSource.rutube => const PlatformAccount(
      login: 'https://rutube.ru/',
      domains: ['https://rutube.ru', 'https://id.rutube.ru'],
    ),
    ReelsSource.shorts => null,
  };

  /// Вошли ли: true/false, null — не знаем.
  Future<bool?> signedIn() async {
    final s = session;
    if (s == null) return null;
    try {
      final c = await CookieManager.instance().getCookie(
        url: WebUri(s.url),
        name: s.name,
      );
      return c != null && '${c.value}'.isNotEmpty;
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    final cm = CookieManager.instance();
    for (final d in domains) {
      try {
        await cm.deleteCookies(url: WebUri(d));
      } catch (_) {}
    }
  }
}

/// Строка в листе выбора площадки: войти или выйти.
class ForkReelsAccountRow extends StatefulWidget {
  const ForkReelsAccountRow({super.key, required this.source});

  final ReelsSource source;

  @override
  State<ForkReelsAccountRow> createState() => _ForkReelsAccountRowState();
}

class _ForkReelsAccountRowState extends State<ForkReelsAccountRow> {
  bool? _in;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void didUpdateWidget(ForkReelsAccountRow old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _in = null;
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final v = await PlatformAccount.of(widget.source)?.signedIn();
    if (mounted) setState(() => _in = v);
  }

  Future<void> _login() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlatformLoginScreen(source: widget.source),
      ),
    );
    await _check();
  }

  Future<void> _logout() async {
    await PlatformAccount.of(widget.source)?.signOut();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final acc = PlatformAccount.of(widget.source);
    final cs = Theme.of(context).colorScheme;
    final title = widget.source.title;
    if (acc == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
        child: Text(
          ruEn(
            'В $title войти нельзя: Google не пускает вход во встроенных браузерах. Лента учится на том, что вы смотрите.',
            'Google blocks sign-in inside apps, so $title runs without your account. The feed learns from what you watch.',
          ),
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            _in == true
                ? Icons.verified_user_rounded
                : Icons.person_outline_rounded,
            size: 20,
            color: _in == true ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _in == true
                  ? ruEn(
                      'Аккаунт $title подключён — лента ваша',
                      'Your $title account is connected',
                    )
                  : ruEn(
                      'Войдите в $title, чтобы лента была по вашим вкусам',
                      'Sign in to $title for your own feed',
                    ),
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
          if (_in != true)
            TextButton(
              onPressed: _login,
              child: Text(ruEn('Войти', 'Sign in')),
            ),
          if (_in != false)
            TextButton(
              onPressed: _logout,
              child: Text(ruEn('Выйти', 'Sign out')),
            ),
        ],
      ),
    );
  }
}

/// Страница входа площадки в видимом окне.
class PlatformLoginScreen extends StatefulWidget {
  const PlatformLoginScreen({super.key, required this.source});

  final ReelsSource source;

  @override
  State<PlatformLoginScreen> createState() => _PlatformLoginScreenState();
}

class _PlatformLoginScreenState extends State<PlatformLoginScreen> {
  static const String _desktopUa =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    // TikTok из России открывается только через посредника лент.
    unawaited(ReelsProxy.enable());
  }

  @override
  void dispose() {
    unawaited(ReelsProxy.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final acc = PlatformAccount.of(widget.source)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ruEn(
            'Вход в ${widget.source.title}',
            'Sign in to ${widget.source.title}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ruEn('Готово', 'Done')),
          ),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(acc.login)),
        initialSettings: InAppWebViewSettings(
          // Как у скрытой ленты: иначе площадка выдаст другую сессию.
          userAgent: widget.source.desktop ? _desktopUa : null,
          javaScriptEnabled: true,
          thirdPartyCookiesEnabled: true,
        ),
        onProgressChanged: (_, p) => setState(() => _progress = p / 100),
      ),
    );
  }
}
