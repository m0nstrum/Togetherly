/// Все адреса сервера форка в одном месте (docs/fork/PLAN.md, S1).
///
/// Значения задаются при сборке:
///
/// ```sh
/// flutter build apk --dart-define-from-file=env/prod.json
/// ```
///
/// Пример файла — `env/example.json`. Дефолтов на сервер апстрима нет: без
/// обязательного значения приложение не стартует ([ensureConfigured]), а
/// необязательное пустое значение выключает свою функцию.
library;

/// Конфиг из `--dart-define`. Чистая логика (разбор, производные адреса)
/// живёт в [EndpointsConfig], чтобы её можно было проверить тестом с любыми
/// значениями, а не только с теми, что пришли в сборку.
abstract final class Endpoints {
  /// Сборочный конфиг. Тесты берут свой через [EndpointsConfig.new].
  static const EndpointsConfig current = EndpointsConfig(
    pbUrl: String.fromEnvironment('PB_URL'),
    centrifugoWs: String.fromEnvironment('CENTRIFUGO_WS'),
    siteUrl: String.fromEnvironment('SITE_URL'),
    legacyHosts: String.fromEnvironment('LEGACY_HOSTS'),
    gamesUrl: String.fromEnvironment('GAMES_URL'),
    reelsProxyUrl: String.fromEnvironment('REELS_PROXY_URL'),
    releasesUrl: String.fromEnvironment('RELEASES_URL'),
    supportEmail: String.fromEnvironment('SUPPORT_EMAIL'),
    sentryDsn: String.fromEnvironment('SENTRY_DSN'),
    mapTileJsonUrl: String.fromEnvironment('MAP_TILEJSON_URL'),
    mapTilesFallback: String.fromEnvironment('MAP_TILES_FALLBACK'),
  );

  /// Адрес PocketBase. Константа: на неё ссылаются `static const` апстрима.
  static const String pbUrl = String.fromEnvironment('PB_URL');

  /// Падает с понятной ошибкой, если сборка без обязательных адресов.
  /// Зовётся первой строкой `main()`.
  static void ensureConfigured() => current.ensureValid();
}

/// Набор адресов и всё, что из них выводится.
class EndpointsConfig {
  const EndpointsConfig({
    required this.pbUrl,
    this.centrifugoWs = '',
    this.siteUrl = '',
    this.legacyHosts = '',
    this.gamesUrl = '',
    this.reelsProxyUrl = '',
    this.releasesUrl = '',
    this.supportEmail = '',
    this.sentryDsn = '',
    String mapTileJsonUrl = '',
    String mapTilesFallback = '',
  }) : _mapTileJsonUrl = mapTileJsonUrl,
       _mapTilesFallback = mapTilesFallback;

  /// `PB_URL`, обязательный. `https://pb.example.org` без `/` в конце.
  final String pbUrl;

  /// `CENTRIFUGO_WS`. Пусто — `wss://<хост PB>/connection/websocket`.
  final String centrifugoWs;

  /// `SITE_URL`: сайт с приглашениями, юридическими страницами и комнатами
  /// «Смотрим вместе». Пусто — тот же адрес, что у PB.
  final String siteUrl;

  /// `LEGACY_HOSTS`: через запятую. Старые домены этого же инстанса, чьи
  /// ссылки (файлы, приглашения) ещё лежат в записях и переписках.
  final String legacyHosts;

  /// `GAMES_URL`. Пусто — вход в игры скрыт.
  final String gamesUrl;

  /// `REELS_PROXY_URL`: прокси для TikTok (`http://host:port`). Пусто — без
  /// прокси.
  final String reelsProxyUrl;

  /// `RELEASES_URL`: страница со свежим APK. Пусто — кнопки обновления нет.
  final String releasesUrl;

  /// `SUPPORT_EMAIL`. Пусто — пункт поддержки скрыт.
  final String supportEmail;

  /// `SENTRY_DSN`. Пусто — крашрепорты выключены.
  final String sentryDsn;

  /// `MAP_TILEJSON_URL`, `MAP_TILES_FALLBACK`.
  final String _mapTileJsonUrl;
  final String _mapTilesFallback;
  String get mapTileJsonUrl =>
      _mapTileJsonUrl.isEmpty ? '$_pb/api/fork/map/tilejson' : _mapTileJsonUrl;
  String get mapTilesFallback => _mapTilesFallback.isEmpty
      ? '$_pb/api/fork/map/tiles/latest/{z}/{x}/{y}.pbf'
      : _mapTilesFallback;

  /// Map sources (including cached TileJSON) must remain on our server.
  bool isOwnMapUrl(String raw) {
    final u = Uri.tryParse(raw);
    return u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.userInfo.isEmpty &&
        ownHosts.contains(u.host.toLowerCase());
  }

  String get _pb => _trimSlash(pbUrl);

  /// Сайт без `/` в конце.
  String get site => _trimSlash(siteUrl.isNotEmpty ? siteUrl : pbUrl);

  /// Хост сайта: ему одному отдаём сессию в комнатах «Смотрим вместе».
  String get siteHost => _host(site);

  /// Адрес WebSocket Centrifugo.
  String get centrifugoUrl {
    if (centrifugoWs.isNotEmpty) return centrifugoWs;
    final u = Uri.tryParse(_pb);
    if (u == null || u.host.isEmpty) return '';
    return u
        .replace(
          scheme: u.scheme == 'http' ? 'ws' : 'wss',
          path: '/connection/websocket',
        )
        .toString();
  }

  /// Хосты, чьи адреса считаем своими: PB, сайт и легаси-домены.
  List<String> get ownHosts => {
    _host(_pb),
    siteHost,
    for (final h in legacyHosts.split(',')) h.trim().toLowerCase(),
  }.where((h) => h.isNotEmpty).toList(growable: false);

  /// Ссылка-приглашение. Пустой код — пустая строка: ссылка без кода ведёт
  /// в 404, а отправитель этого не видит.
  ///
  /// Во фрагменте — секрет приглашения и отпечаток ключа (E2E.md §6.2):
  /// фрагмент не уходит на сервер ни из браузера, ни из приложения.
  String inviteLink(String code, {String fragment = ''}) {
    if (code.trim().isEmpty || site.isEmpty) return '';
    return fragment.isEmpty
        ? '$site/invite/$code'
        : '$site/invite/$code#$fragment';
  }

  String get privacyPolicyUrl => site.isEmpty ? '' : '$site/privacy-policy';
  String get termsUrl => site.isEmpty ? '' : '$site/terms';

  /// Лендинг (раздел «о приложении»).
  String get aboutUrl => site.isEmpty ? '' : '$site/#download';

  /// Чего не хватает или что задано неверно. Пусто — конфиг годный.
  List<String> problems() {
    final out = <String>[];
    if (pbUrl.isEmpty) {
      out.add('PB_URL не задан');
    } else if (!_isHttpUrl(pbUrl)) {
      out.add('PB_URL должен быть http(s)-адресом: "$pbUrl"');
    }
    if (siteUrl.isNotEmpty && !_isHttpUrl(siteUrl)) {
      out.add('SITE_URL должен быть http(s)-адресом: "$siteUrl"');
    }
    if (centrifugoWs.isNotEmpty) {
      final u = Uri.tryParse(centrifugoWs);
      if (u == null ||
          !(u.scheme == 'ws' || u.scheme == 'wss') ||
          u.host.isEmpty) {
        out.add('CENTRIFUGO_WS должен быть ws(s)-адресом: "$centrifugoWs"');
      }
    }
    for (final (name, v) in [
      ('GAMES_URL', gamesUrl),
      ('REELS_PROXY_URL', reelsProxyUrl),
      ('RELEASES_URL', releasesUrl),
    ]) {
      if (v.isNotEmpty && !_isHttpUrl(v)) {
        out.add('$name должен быть http(s)-адресом: "$v"');
      }
    }
    for (final (name, value) in [
      ('MAP_TILEJSON_URL', _mapTileJsonUrl),
      ('MAP_TILES_FALLBACK', _mapTilesFallback),
    ]) {
      if (value.isNotEmpty && !isOwnMapUrl(value))
        out.add('$name должен указывать на свой сервер');
    }
    return out;
  }

  void ensureValid() {
    final p = problems();
    if (p.isEmpty) return;
    throw StateError(
      'Сборка без адресов сервера: ${p.join('; ')}.\n'
      'Соберите с --dart-define-from-file=env/<name>.json '
      '(пример — env/example.json, описание — docs/fork/README.md).',
    );
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static String _host(String url) =>
      (Uri.tryParse(url)?.host ?? '').toLowerCase();

  static bool _isHttpUrl(String s) {
    final u = Uri.tryParse(s);
    return u != null &&
        (u.scheme == 'https' || u.scheme == 'http') &&
        u.host.isNotEmpty;
  }
}
