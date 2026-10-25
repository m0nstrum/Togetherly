import '../models/wish_place.dart';

/// Точка из ссылки на карты (docs/WISHLIST.md, «Поделиться → Tethered»):
/// Яндекс Карты, Google Maps, 2ГИС, OpenStreetMap, Apple Maps и `geo:`.
///
/// Разбирается только то, что есть в самом адресе. Короткие ссылки
/// (`maps.app.goo.gl`, `yandex.ru/maps/-/…`) сначала раскрываются шлюзом
/// превью — он отдаёт итоговый адрес. Null — точки в адресе нет.
WishPlace? mapPointFromUrl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // geo:55.75,37.61?q=… и geo:0,0?q=55.75,37.61(Название)
  if (s.toLowerCase().startsWith('geo:')) {
    final body = s.substring(4);
    final q = Uri.tryParse(
      'x:?${body.contains('?') ? body.split('?')[1] : ''}',
    )?.queryParameters['q'];
    final fromQ = _pair(q, latFirst: true);
    if (fromQ != null) return _named(fromQ, _label(q));
    return _pair(body.split('?').first, latFirst: true);
  }

  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  final qp = uri.queryParameters;

  // Яндекс: pt=lng,lat (метка) или ll=lng,lat (центр) — долгота первой.
  if (host.contains('yandex.') || host.contains('ya.ru')) {
    final p =
        _pair(qp['pt'], latFirst: false) ??
        _pair(qp['whatshere[point]'], latFirst: false) ??
        _pair(qp['ll'], latFirst: false);
    if (p != null) return p;
  }

  // 2ГИС: m=lng,lat/zoom — тоже долгота первой.
  if (host.contains('2gis.')) {
    final m = qp['m']?.split('/').first;
    final p = _pair(m, latFirst: false);
    if (p != null) return p;
    final path = RegExp(r'/geo/(-?\d+\.\d+)%2C(-?\d+\.\d+)').firstMatch(s);
    if (path != null) {
      return _make(double.parse(path[2]!), double.parse(path[1]!));
    }
  }

  // OpenStreetMap: mlat/mlon или #map=zoom/lat/lng.
  if (host.contains('openstreetmap.')) {
    final p = _make(
      double.tryParse(qp['mlat'] ?? ''),
      double.tryParse(qp['mlon'] ?? ''),
    );
    if (p != null) return p;
    final frag = RegExp(
      r'map=\d+(?:\.\d+)?/(-?\d+\.\d+)/(-?\d+\.\d+)',
    ).firstMatch(uri.fragment);
    if (frag != null) {
      return _make(double.parse(frag[1]!), double.parse(frag[2]!));
    }
  }

  // Apple: ll=lat,lng или q=lat,lng.
  if (host.contains('maps.apple.')) {
    final p =
        _pair(qp['ll'], latFirst: true) ??
        _pair(qp['coordinate'], latFirst: true) ??
        _pair(qp['q'], latFirst: true);
    if (p != null)
      return _named(
        p,
        qp['q'] != null && _pair(qp['q'], latFirst: true) == null
            ? qp['q']!
            : '',
      );
  }

  // Google: !3dLAT!4dLNG (точка места) точнее, чем @lat,lng (центр карты);
  // ещё бывают q=/query=/ll=lat,lng.
  if (host.contains('google.') || host.contains('goo.gl')) {
    final d = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(s);
    if (d != null) {
      return _named(
        _make(double.parse(d[1]!), double.parse(d[2]!))!,
        _googleName(uri),
      );
    }
    final at = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(s);
    if (at != null) {
      return _named(
        _make(double.parse(at[1]!), double.parse(at[2]!))!,
        _googleName(uri),
      );
    }
    final p =
        _pair(qp['q'], latFirst: true) ??
        _pair(qp['query'], latFirst: true) ??
        _pair(qp['ll'], latFirst: true) ??
        _pair(qp['destination'], latFirst: true);
    if (p != null) return p;
  }
  return null;
}

/// «55.75,37.61» → точка. [latFirst] — широта первой (у Яндекса и 2ГИС
/// наоборот).
WishPlace? _pair(String? raw, {required bool latFirst}) {
  if (raw == null) return null;
  final m = RegExp(
    r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
  ).firstMatch(_decode(raw.replaceAll('+', ' ')));
  if (m == null) return null;
  final a = double.parse(m[1]!), b = double.parse(m[2]!);
  return latFirst ? _make(a, b) : _make(b, a);
}

/// Значение из адреса бывает уже раскодированным — тогда «%» в нём не
/// экранирование, и повторное декодирование падает.
String _decode(String v) {
  try {
    return Uri.decodeComponent(v);
  } on ArgumentError {
    return v;
  }
}

WishPlace? _make(double? lat, double? lng) {
  if (lat == null || lng == null) return null;
  final p = WishPlace(lat: lat, lng: lng);
  return p.valid ? p : null;
}

WishPlace _named(WishPlace p, String name) => name.isEmpty
    ? p
    : WishPlace(
        lat: p.lat,
        lng: p.lng,
        name: name.length > 80 ? name.substring(0, 80) : name,
      );

/// `geo:…?q=55.7,37.6(Парк)` → «Парк».
String _label(String? q) {
  if (q == null) return '';
  final m = RegExp(r'\(([^)]*)\)').firstMatch(q);
  return m == null ? '' : m[1]!.trim();
}

/// `/maps/place/Парк+Горького/@…` → «Парк Горького».
String _googleName(Uri uri) {
  final i = uri.pathSegments.indexOf('place');
  if (i < 0 || i + 1 >= uri.pathSegments.length) return '';
  final seg = uri.pathSegments[i + 1];
  if (seg.startsWith('@')) return '';
  return seg.replaceAll('+', ' ').trim();
}
