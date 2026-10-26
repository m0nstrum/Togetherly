import 'dart:convert';
import 'dart:math' as math;

/// Точка «Места» в вишлисте (docs/WISHLIST.md): где это, на своей карте
/// приложения. В записи — JSON строкой в `wishes.place`, шифр ключа пары:
/// сервер не знает, куда пара собирается.
class WishPlace {
  const WishPlace({required this.lat, required this.lng, this.name = ''});

  final double lat;
  final double lng;

  /// Подпись: адрес или «у фонтана». Не обязательна.
  final String name;

  bool get valid =>
      lat.isFinite &&
      lng.isFinite &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      !(lat == 0 && lng == 0);

  String encode() => jsonEncode({
    'lat': double.parse(lat.toStringAsFixed(6)),
    'lng': double.parse(lng.toStringAsFixed(6)),
    if (name.isNotEmpty) 'name': name,
  });

  /// Пусто или не читается — null.
  static WishPlace? parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    try {
      final m = jsonDecode(s);
      if (m is! Map) return null;
      final p = WishPlace(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        name: (m['name'] ?? '').toString(),
      );
      return p.valid ? p : null;
    } on Object {
      return null;
    }
  }

  /// Расстояние по большому кругу, метров.
  double metersTo(double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat), dLng = rad(lng2 - lng);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1, math.sqrt(a)));
  }

  @override
  bool operator ==(Object other) =>
      other is WishPlace &&
      other.lat == lat &&
      other.lng == lng &&
      other.name == name;

  @override
  int get hashCode => Object.hash(lat, lng, name);
}
