import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../utils/safe_launch.dart';

/// OSM stays visible; the menu also credits the tile service and schema.
class ForkMapAttribution extends StatelessWidget {
  const ForkMapAttribution({super.key});
  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.textScalerOf(context).scale(11) * 1.4).clamp(24.0, double.infinity);
    void open(String url) { safeLaunchUrl(Uri.parse(url)); }
    return RichAttributionWidget(
      showFlutterMapAttribution: false, permanentHeight: height,
      popupBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      attributions: [
        LogoSourceAttribution(
          Text('© OpenStreetMap', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface)),
          height: height, onTap: () => open('https://www.openstreetmap.org/copyright')),
        TextSourceAttribution('OpenStreetMap contributors', onTap: () => open('https://www.openstreetmap.org/copyright')),
        TextSourceAttribution('OpenFreeMap', prependCopyright: false, onTap: () => open('https://openfreemap.org/')),
        TextSourceAttribution('OpenMapTiles', onTap: () => open('https://openmaptiles.org/')),
      ],
    );
  }
}
