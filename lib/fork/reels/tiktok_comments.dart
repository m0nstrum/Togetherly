/// Комментарии TikTok для совместной ленты (просьба владельца 22.10).
///
/// Берём их тем же путём, что и саму ленту: браузером приложения на
/// tiktok.com. Тогда работают те же куки (вход в аккаунт площадки), тот же
/// посредник, если он включён ([ReelsProxy]), а сервер пары не узнаёт, какие
/// ролики пара смотрит. Страница браузера — крошечный `robots.txt`: нужен
/// только адрес tiktok.com, чтобы запрос к его API шёл «своим».
///
/// API площадки отдаёт много лишнего; странице ленты уходит сжатый ответ
/// ([parse]): кто, что, когда, сколько лайков и ответов.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ForkTikTokComments {
  ForkTikTokComments({@visibleForTesting Future<String?> Function(String path)? fetch}) : _fetch = fetch;

  final Future<String?> Function(String path)? _fetch;

  static const String _home = 'https://www.tiktok.com/robots.txt';
  static const String _desktopUa =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36';
  static final RegExp _num = RegExp(r'^\d{5,25}$');

  HeadlessInAppWebView? _view;
  Completer<InAppWebViewController?>? _ready;
  bool _disposed = false;

  /// Страница комментариев ролика [id] или ответов на комментарий [cid].
  /// Ответ — для страницы ленты: `{ok, total, cursor, more, items}` или
  /// `{ok: false, why: 'blocked' | 'failed'}`.
  Future<Map<String, dynamic>> page({required String id, String cid = '', int cursor = 0}) async {
    if (!_num.hasMatch(id) || (cid.isNotEmpty && !_num.hasMatch(cid)) || cursor < 0) {
      return const {'ok': false, 'why': 'failed'};
    }
    final path = cid.isEmpty
        ? '/api/comment/list/?aid=1988&aweme_id=$id&count=20&cursor=$cursor'
        : '/api/comment/list/reply/?aid=1988&item_id=$id&comment_id=$cid&count=10&cursor=$cursor';
    // Площадка изредка отвечает пустым телом — второй раз обычно отдаёт.
    for (var attempt = 0; attempt < 2; attempt++) {
      final body = await _get(path);
      if (body != null && body.trim().isNotEmpty) return parse(body);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    return const {'ok': false, 'why': 'failed'};
  }

  Future<String?> _get(String path) async {
    final f = _fetch;
    if (f != null) return f(path);
    final c = await _controller();
    if (c == null) return null;
    try {
      final r = await c
          .callAsyncJavaScript(
            functionBody: "const r = await fetch(p, {credentials: 'include'}); return await r.text();",
            arguments: {'p': path},
          )
          .timeout(const Duration(seconds: 15));
      if (r?.error != null) {
        debugPrint('ForkTikTokComments: ${r!.error}');
        return null;
      }
      final v = r?.value;
      return v is String ? v : null;
    } catch (e) {
      debugPrint('ForkTikTokComments: запрос не вышел: $e');
      return null;
    }
  }

  /// Браузер на tiktok.com — один на открытую ленту, поднимается по первому
  /// вопросу.
  Future<InAppWebViewController?> _controller() {
    if (_disposed) return Future.value(null);
    final ready = _ready;
    if (ready != null) return ready.future;
    final done = Completer<InAppWebViewController?>();
    _ready = done;
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_home)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _desktopUa,
        useOnRenderProcessGone: true,
      ),
      onLoadStop: (c, _) {
        if (!done.isCompleted) done.complete(c);
      },
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) {
          debugPrint('ForkTikTokComments: tiktok.com не открылся: ${err.description}');
          if (!done.isCompleted) done.complete(null);
          _ready = null; // в следующий раз попробуем заново
        }
      },
      onRenderProcessGone: (_, _) {
        _ready = null;
        unawaited(_view?.dispose());
        _view = null;
      },
    );
    _view = view;
    unawaited(view.run().catchError((Object e) {
      debugPrint('ForkTikTokComments: браузер не поднялся: $e');
      if (!done.isCompleted) done.complete(null);
      _ready = null;
    }));
    // Не открылся за 20 с — считаем неудачей, а не ждём вечно.
    Future<void>.delayed(const Duration(seconds: 20), () {
      if (!done.isCompleted) {
        done.complete(null);
        _ready = null;
      }
    });
    return done.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    final view = _view;
    _view = null;
    _ready = null;
    if (view != null) {
      try {
        await view.dispose();
      } catch (_) {
        // тихо: браузер уже закрыт
      }
    }
  }

  /// Ответ API площадки → то, что рисует лист комментариев.
  static Map<String, dynamic> parse(String body) {
    if (body.contains('cross_border_block')) return const {'ok': false, 'why': 'blocked'};
    Object? raw;
    try {
      raw = jsonDecode(body);
    } catch (_) {
      return const {'ok': false, 'why': 'failed'};
    }
    if (raw is! Map) return const {'ok': false, 'why': 'failed'};
    final code = raw['status_code'];
    if (code is num && code != 0) {
      return {'ok': false, 'why': code == 10204 ? 'blocked' : 'failed'};
    }
    final list = raw['comments'];
    final items = <Map<String, dynamic>>[];
    if (list is List) {
      for (final c in list) {
        if (c is! Map) continue;
        final cid = '${c['cid'] ?? ''}';
        if (cid.isEmpty) continue;
        final user = c['user'] is Map ? c['user'] as Map : const {};
        final thumbs = user['avatar_thumb'] is Map ? (user['avatar_thumb'] as Map)['url_list'] : null;
        final avatar = thumbs is List && thumbs.isNotEmpty ? '${thumbs.first}' : '';
        final images = c['image_list'];
        items.add({
          'cid': cid,
          'name': '${user['nickname'] ?? user['unique_id'] ?? ''}'.trim(),
          'avatar': avatar.startsWith('https://') ? avatar : '',
          'text': '${c['text'] ?? ''}',
          'likes': _int(c['digg_count']),
          'replies': _int(c['reply_comment_total']),
          'time': _int(c['create_time']),
          'authorLiked': c['is_author_digged'] == true,
          'pinned': c['author_pin'] == true || _int(c['stick_position']) > 0,
          'photo': images is List && images.isNotEmpty,
        });
      }
    }
    return {
      'ok': true,
      'total': _int(raw['total']),
      'cursor': _int(raw['cursor']),
      'more': _int(raw['has_more']) == 1 || raw['has_more'] == true,
      'items': items,
    };
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
}
