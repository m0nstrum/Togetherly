/// Прокси роликов «Смотрим вместе» (PLAN S11).
///
/// Если оператор включил прокси на сервере, браузер комнаты ходит к
/// площадкам (YouTube, Vimeo) через него: снаружи виден только TLS к нашему
/// домену, TLS до площадки сквозной. Через прокси идут только площадки из
/// списка сервера (обратный обход `ProxyController`); всё остальное — как
/// обычно. Действует, пока открыта комната.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/pocketbase_service.dart';

/// Что сервер сказал о прокси.
class WatchProxyInfo {
  const WatchProxyInfo({required this.url, required this.hosts});

  final Uri url;

  /// Белый список сервера: `.x` — домен и поддомены.
  final List<String> hosts;

  static WatchProxyInfo? fromJson(Object? j) {
    if (j is! Map || j['enabled'] != true) return null;
    final url = Uri.tryParse('${j['url'] ?? ''}');
    final hosts = j['hosts'];
    if (url == null || url.host.isEmpty || hosts is! List) return null;
    return WatchProxyInfo(url: url, hosts: [for (final h in hosts) '$h']);
  }

  /// Правила `ProxyController` для хостов из списка.
  List<String> get rules => [
    for (final h in hosts)
      if (h.startsWith('.')) ...[h.substring(1), '*$h'] else h,
  ];
}

abstract final class ForkWatchProxy {
  static WatchProxyInfo? _active;
  static int _users = 0;

  /// Включить на время комнаты. Ничего не делает, если сервер прокси не
  /// предлагает или телефон не умеет пускать через прокси только часть
  /// адресов (тогда в прокси ушло бы всё, включая наш же сервер).
  static Future<void> enable() async {
    _users++;
    if (!Platform.isAndroid || _active != null) return;
    try {
      final info = WatchProxyInfo.fromJson(
        await PocketBaseService().pb.send('/api/fork/watch-proxy'),
      );
      if (info == null) return;
      final ok =
          await WebViewFeature.isFeatureSupported(
            WebViewFeature.PROXY_OVERRIDE,
          ) &&
          await WebViewFeature.isFeatureSupported(
            WebViewFeature.PROXY_OVERRIDE_REVERSE_BYPASS,
          );
      if (!ok || _users == 0) return;
      await ProxyController.instance().setProxyOverride(
        settings: ProxySettings(
          proxyRules: [ProxyRule(url: info.url.toString())],
          bypassRules: info.rules,
          reverseBypassEnabled: true,
        ),
      );
      _active = info;
    } catch (e) {
      debugPrint('ForkWatchProxy: не включился — $e');
    }
  }

  /// Комната закрыта.
  static Future<void> disable() async {
    if (_users > 0) _users--;
    if (_users > 0 || _active == null) return;
    _active = null;
    try {
      await ProxyController.instance().clearProxyOverride();
    } catch (e) {
      debugPrint('ForkWatchProxy: не снялся — $e');
    }
  }

  /// Вход на прокси: Basic `uid:токен`. null — запрос не от нашего прокси.
  static HttpAuthResponse? answer(URLAuthenticationChallenge challenge) {
    final p = _active;
    final space = challenge.protectionSpace;
    if (p == null || space.host != p.url.host) return null;
    if (space.port != null && space.port != p.url.port) return null;
    final pb = PocketBaseService();
    final uid = pb.userId ?? '';
    final token = pb.pb.authStore.token;
    if (uid.isEmpty || token.isEmpty) return null;
    return HttpAuthResponse(
      username: uid,
      password: token,
      action: HttpAuthResponseAction.PROCEED,
    );
  }
}
