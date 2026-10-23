import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/pocketbase_service.dart';
import 'config/endpoints.dart';
import 'flags.dart';
import 'meta_direct.dart';

/// Все запросы приложения к сторонним сайтам — через свой сервер
/// (meta gateway, docs/fork/PLAN.md S5).
///
/// Перехватывает `dart:io` целиком (`HttpOverrides`), то есть и
/// `package:http`, и `Image.network`, и всё, что апстрим добавит позже, — без
/// правок в его файлах. Сторонний сервис видит IP сервера, а не человека.
///
/// Прямыми остаются: свой сервер и его старые домены, Centrifugo, Bugsink
/// (DSN), локальные адреса. WebView и
/// нативные плееры сюда не попадают — это осознанное исключение решения 4.
///
/// Настройка «Ссылки напрямую с устройства» ([ForkMetaDirect]) выключает
/// перехват на лету.
///
/// Перехватываются только GET и HEAD: остальные методы к чужим сайтам
/// приложение не шлёт, а слать их через сервер незачем.
abstract final class ForkHttpGateway {
  /// Ставит перехват в текущем изоляте. Повторный вызов ничего не делает.
  /// Звать до первых запросов: из `PocketBaseService.init`, которую зовут все
  /// изоляты (главный, push-сервис, WorkManager).
  static void install() {
    if (!ForkFlags.metaGateway || _installed) return;
    final cfg = Endpoints.current;
    if (cfg.pbUrl.isEmpty) return;
    final pb = cfg.pbUrl.endsWith('/')
        ? cfg.pbUrl.substring(0, cfg.pbUrl.length - 1)
        : cfg.pbUrl;
    HttpOverrides.global = overrides(
      gateway: Uri.parse('$pb/api/meta/fetch'),
      direct: directHosts(cfg),
    );
    _installed = true;
    unawaited(ForkMetaDirect.load());
  }

  static bool _installed = false;

  /// Перехват с заданным gateway: для [install] и тестов.
  @visibleForTesting
  static HttpOverrides overrides({
    required Uri gateway,
    required Set<String> direct,
  }) => _GatewayOverrides(
    gateway: gateway,
    direct: direct,
    previous: HttpOverrides.current,
  );

  /// Хосты, к которым ходим напрямую.
  @visibleForTesting
  static Set<String> directHosts(EndpointsConfig cfg) => {
    ...cfg.ownHosts,
    _host(cfg.centrifugoUrl),
    _host(cfg.sentryDsn),
    'localhost',
    '127.0.0.1',
    '10.0.2.2',
  }..remove('');

  static String _host(String url) =>
      (Uri.tryParse(url)?.host ?? '').toLowerCase();

  /// Куда на самом деле идёт GET/HEAD к [url]: адрес gateway или null —
  /// напрямую.
  @visibleForTesting
  static Uri? route(
    Uri url, {
    required Uri gateway,
    required Set<String> direct,
  }) {
    if (url.scheme != 'http' && url.scheme != 'https') return null;
    if (direct.contains(url.host.toLowerCase())) return null;
    return gateway.replace(queryParameters: {'url': url.toString()});
  }
}

class _GatewayOverrides extends HttpOverrides {
  _GatewayOverrides({
    required this.gateway,
    required this.direct,
    this.previous,
  });

  final Uri gateway;
  final Set<String> direct;
  final HttpOverrides? previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    return _GatewayHttpClient(inner, gateway, direct);
  }
}

/// [HttpClient], который отправляет GET/HEAD к чужим сайтам на gateway.
class _GatewayHttpClient implements HttpClient {
  _GatewayHttpClient(this._inner, this._gateway, this._direct);

  final HttpClient _inner;
  final Uri _gateway;
  final Set<String> _direct;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final m = method.toUpperCase();
    final via = (m == 'GET' || m == 'HEAD') && !ForkMetaDirect.enabled.value
        ? ForkHttpGateway.route(url, gateway: _gateway, direct: _direct)
        : null;
    if (via == null) return _inner.openUrl(method, url);
    final req = await _inner.openUrl(method, via);
    final token = _token();
    if (token.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, token);
    }
    return _GatewayRequest(req);
  }

  static String _token() {
    try {
      return PocketBaseService().pb.authStore.token;
    } catch (_) {
      return '';
    }
  }

  Uri _uri(String host, int port, String path) {
    final q = path.indexOf('?');
    return Uri(
      scheme: port == HttpClient.defaultHttpsPort ? 'https' : 'http',
      host: host,
      port: port,
      path: q < 0 ? path : path.substring(0, q),
      query: q < 0 ? null : path.substring(q + 1),
    );
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, _uri(host, port, path));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}

/// Запрос через gateway. Если вызывающий выключил `followRedirects` (так
/// апстрим раскрывает короткие ссылки, читая `Location`), просит сервер не
/// проходить редирект сам, а вернуть 3xx — следующий шаг клиент снова
/// сделает через gateway.
class _GatewayRequest implements HttpClientRequest {
  _GatewayRequest(this._inner);

  final HttpClientRequest _inner;

  @override
  Future<HttpClientResponse> close() {
    if (!_inner.followRedirects) {
      _inner.headers.set('X-Meta-Redirect', 'manual');
    }
    return _inner.close();
  }

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool v) => _inner.persistentConnection = v;
  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool v) => _inner.followRedirects = v;
  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int v) => _inner.maxRedirects = v;
  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int v) => _inner.contentLength = v;
  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool v) => _inner.bufferOutput = v;
  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding v) => _inner.encoding = v;
  @override
  String get method => _inner.method;
  @override
  Uri get uri => _inner.uri;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  Future<HttpClientResponse> get done => _inner.done;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future<void> flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
}
