/// Настройка «Ссылки напрямую с устройства» (docs/fork/PLAN.md, meta gateway).
///
/// По умолчанию выключена: к сторонним сайтам ходит свой сервер
/// (`http_gateway.dart`), сайт видит IP сервера, а сервер — саму ссылку.
/// Включённая — наоборот: запросы идут с телефона, сервер ссылок не видит,
/// а сайты видят IP человека. Карточку товара тогда разбирает
/// [ForkLinkPreview] на устройстве — тем же разбором, что сервер
/// (`server/internal/domain/linkpreview`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_service.dart';
import '../widgets/settings_scaffold.dart';
import 'flags.dart';

abstract final class ForkMetaDirect {
  static const String prefsKey = 'fork_meta_direct';

  /// Включена ли настройка. До [load] — false: безопасный вариант.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(prefsKey) ?? false;
    } catch (_) {} // тихо: без настроек — значение по умолчанию
  }

  static Future<void> set(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, value);
    } catch (_) {} // тихо: переключатель в памяти уже сменён
  }
}

/// Карточка товара по ссылке на устройстве. Ответ — в форме
/// `/api/link/preview`: форма желания читает его без изменений.
abstract final class ForkLinkPreview {
  /// null — страница не открылась: форма даст заполнить руками.
  static Future<Map<String, dynamic>?> fetch(
    String url, {
    http.Client? client,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    final c = client ?? http.Client();
    try {
      final resp = await c
          .get(uri, headers: {'Accept-Language': 'ru,en;q=0.8'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final html = resp.body;
      return {'success': true, ...parse(html, uri.toString())};
    } catch (e) {
      debugPrint('ForkLinkPreview: $e');
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Разбор HTML — порт `linkpreview.Parse` один в один.
  @visibleForTesting
  static Map<String, dynamic> parse(String html, String pageUrl) {
    final u = Uri.tryParse(pageUrl);
    final host = (u?.host ?? '').toLowerCase();

    var title = _unescape(_meta(html, ['og:title', 'twitter:title']));
    if (title.isEmpty) {
      final m = _titleRe.firstMatch(html);
      if (m != null) title = _unescape(m.group(1)!);
    }
    var image = _unescape(
      _meta(html, ['og:image', 'og:image:secure_url', 'twitter:image']),
    );
    var site = _unescape(_meta(html, ['og:site_name']));
    if (site.isEmpty) {
      site = host.startsWith('www.') ? host.substring(4) : host;
    }
    var price = _unescape(
      _meta(html, [
        'product:price:amount',
        'og:price:amount',
        'price',
        'twitter:data1',
      ]),
    );
    var currency = _unescape(
      _meta(html, [
        'product:price:currency',
        'og:price:currency',
        'priceCurrency',
      ]),
    );
    if (price.isEmpty) price = _ldPriceRe.firstMatch(html)?.group(1) ?? '';
    if (currency.isEmpty) {
      currency = _ldCurrencyRe.firstMatch(html)?.group(1) ?? '';
    }

    var cur = currency.toUpperCase();
    final head = html.length <= 60000 ? html : html.substring(0, 60000);
    if (cur.isEmpty && _rubRe.hasMatch(head)) cur = 'RUB';
    final sign = _signs[cur] ?? cur;

    if (image.isNotEmpty &&
        !image.startsWith('//') &&
        !image.startsWith('http') &&
        u != null) {
      final origin = '${u.scheme}://$host';
      image = image.startsWith('/') ? '$origin$image' : '$origin/$image';
    }
    if (image.startsWith('//')) image = 'https:$image';

    return {
      'title': _cut(title, 120),
      'image': _cut(image, 500),
      'shop': _cut(site, 80),
      'price': _amount(price),
      'currency': sign,
    };
  }

  static final _titleRe = RegExp(
    r'<title[^>]*>(.{0,300}?)</title>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _ldPriceRe = RegExp(
    r'"price"\s*:\s*"?([0-9][0-9\s.,]*)"?',
    caseSensitive: false,
  );
  static final _ldCurrencyRe = RegExp(
    r'"priceCurrency"\s*:\s*"([A-Za-z]{3})"',
    caseSensitive: false,
  );
  static final _rubRe = RegExp('₽|руб', caseSensitive: false);
  static final _centsRe = RegExp(r'[.,](\d{1,2})$');
  static final _spaceRe = RegExp(r'\s+');
  static const _signs = {
    'RUB': '₽',
    'USD': r'$',
    'EUR': '€',
    'KZT': '₸',
    'BYN': 'Br',
    'UAH': '₴',
  };

  static String _meta(String html, List<String> names) {
    for (final n in names) {
      final q = RegExp.escape(n);
      for (final p in [
        '<meta[^>]+(?:property|name|itemprop)\\s*=\\s*["\']$q["\'][^>]*content\\s*=\\s*["\']([^"\']*)["\']',
        '<meta[^>]+content\\s*=\\s*["\']([^"\']*)["\'][^>]*(?:property|name|itemprop)\\s*=\\s*["\']$q["\']',
      ]) {
        final m = RegExp(p, caseSensitive: false).firstMatch(html);
        final v = m?.group(1) ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  static String _unescape(String s) {
    const entities = {
      '&quot;': '"',
      '&#39;': "'",
      '&#039;': "'",
      '&apos;': "'",
      '&nbsp;': ' ',
      '&lt;': '<',
      '&gt;': '>',
    };
    entities.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll('&amp;', '&');
    return s.replaceAll(_spaceRe, ' ').trim();
  }

  /// Целые единицы: «12 990,00» → 12990, «от 1 299 ₽» → 1299.
  static int _amount(String price) {
    if (price.isEmpty) return 0;
    final digits = price
        .replaceAll(RegExp(r'[^0-9.,]'), '')
        .replaceAll(_centsRe, '');
    final n = int.tryParse(digits.replaceAll(RegExp('[.,]'), '')) ?? 0;
    return n > 0 && n < 1000000000 ? n : 0;
  }

  static String _cut(String s, int n) {
    final r = s.runes;
    return r.length <= n ? s : String.fromCharCodes(r.take(n));
  }
}

/// Переключатель в настройках (раздел «О приложении»).
class ForkMetaDirectRow extends StatelessWidget {
  const ForkMetaDirectRow({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ForkFlags.metaGateway) return const SizedBox.shrink();
    final ru = const {
      'ru',
      'uk',
      'be',
    }.contains(LocaleService.instance.language.code.toLowerCase());
    return ValueListenableBuilder<bool>(
      valueListenable: ForkMetaDirect.enabled,
      builder: (context, value, _) => SettingsRow(
        icon: Icons.link_rounded,
        title: ru ? 'Ссылки напрямую с устройства' : 'Open links from device',
        subtitle: ru
            ? (value
                  ? 'Сервер не видит ссылки, а сайты видят ваш IP'
                  : 'Сайты видят IP сервера, а не ваш')
            : (value
                  ? 'The server doesn\'t see links; sites see your IP'
                  : 'Sites see the server\'s IP, not yours'),
        trailing: Switch(value: value, onChanged: ForkMetaDirect.set),
        onTap: () => ForkMetaDirect.set(!value),
      ),
    );
  }
}
