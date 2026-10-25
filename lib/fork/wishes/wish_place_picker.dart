import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/wish_place.dart';
import '../../services/live_location_service.dart';
import '../../services/map/map_tiles.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';

/// Точка «Места» на своей карте приложения (docs/WISHLIST.md): тап ставит
/// метку, подпись — по желанию. [readOnly] — просто показать, где это.
class WishPlacePicker extends StatefulWidget {
  const WishPlacePicker({
    super.key,
    required this.theme,
    this.initial,
    this.readOnly = false,
    this.tiles,
  });

  final AppTheme theme;
  final WishPlace? initial;
  final bool readOnly;

  /// Для тестов: подложка вместо сетевых тайлов.
  final Widget? tiles;

  static Future<WishPlace?> pick(
    BuildContext context, {
    required AppTheme theme,
    WishPlace? initial,
  }) => Navigator.of(context).push<WishPlace>(
    MaterialPageRoute(
      builder: (_) => WishPlacePicker(theme: theme, initial: initial),
      settings: const RouteSettings(name: '/wishes/place'),
    ),
  );

  static Future<void> show(
    BuildContext context, {
    required AppTheme theme,
    required WishPlace place,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          WishPlacePicker(theme: theme, initial: place, readOnly: true),
      settings: const RouteSettings(name: '/wishes/place'),
    ),
  );

  @override
  State<WishPlacePicker> createState() => _WishPlacePickerState();
}

class _WishPlacePickerState extends State<WishPlacePicker> {
  final MapController _map = MapController();
  late LatLng? _point = widget.initial == null
      ? null
      : LatLng(widget.initial!.lat, widget.initial!.lng);
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  LatLng get _start {
    final p = _point;
    if (p != null) return p;
    final me = LiveLocationService.instance.myFix.value;
    if (me != null) return LatLng(me.latitude, me.longitude);
    return const LatLng(55.7558, 37.6173);
  }

  bool get _knownStart =>
      _point != null || LiveLocationService.instance.myFix.value != null;

  /// «Я здесь»: центр на своей точке и метка туда же.
  Future<void> _here() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final ok = await LiveLocationService.instance.ensurePermission();
      if (!ok) return;
      final pos = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _point = p);
      _map.move(p, 16);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ruEn('Не удалось узнать, где вы', 'Couldn’t get your location'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _done() {
    final p = _point;
    if (p == null) return;
    Navigator.of(context).pop(
      WishPlace(lat: p.latitude, lng: p.longitude, name: _name.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final point = _point;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.readOnly
              ? (widget.initial?.name.isNotEmpty ?? false)
                    ? widget.initial!.name
                    : ruEn('Место', 'Place')
              : ruEn('Где это', 'Where is it'),
          style: AppFonts.unbounded(size: 17, weight: 600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _start,
                    initialZoom: _knownStart ? 15 : 4,
                    minZoom: 2,
                    maxZoom: 18,
                    backgroundColor: mapBackground(widget.theme),
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onTap: widget.readOnly
                        ? null
                        : (_, p) => setState(() => _point = p),
                  ),
                  children: [
                    widget.tiles ?? ThemedMapLayer(theme: widget.theme),
                    if (point != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 48,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Icons.location_on_rounded,
                              size: 48,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (!widget.readOnly)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      heroTag: 'wish-place-here',
                      tooltip: ruEn('Я здесь', 'I’m here'),
                      onPressed: _here,
                      child: _locating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                    ),
                  ),
                if (!widget.readOnly && point == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: 12,
                    child: Material(
                      color: cs.inverseSurface,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          ruEn(
                            'Нажмите на карту, чтобы поставить метку',
                            'Tap the map to drop a pin',
                          ),
                          style: AppFonts.onest(
                            size: 14,
                            color: cs.onInverseSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.readOnly)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('wish-place-name'),
                      controller: _name,
                      maxLength: 80,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: ruEn('Подпись', 'Label'),
                        hintText: ruEn(
                          'адрес или «у фонтана» — не обязательно',
                          'address or “by the fountain” — optional',
                        ),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: const Key('wish-place-done'),
                        onPressed: point == null ? null : _done,
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                        ),
                        child: Text(ruEn('Готово', 'Done')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
