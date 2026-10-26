import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/geo/map_attribution.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'OSM attribution is always visible on a narrow map at scale $scale',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 292,
                  height: 180,
                  child: MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: const FlutterMap(
                      options: MapOptions(),
                      children: [ForkMapAttribution()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('© OpenStreetMap'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
