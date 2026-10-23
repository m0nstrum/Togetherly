import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/fork/config/endpoints.dart';
import 'package:love_app/services/map/map_tiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'external cached and TileJSON sources are rejected; relative own source works',
    () async {
      SharedPreferences.setMockInitialValues({
        'ofm_tiles_template':
            'https://tiles.openfreemap.org/planet/old/{z}/{x}/{y}.pbf',
        'ofm_tiles_template_at': DateTime.now().millisecondsSinceEpoch,
      });
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.toString(), Endpoints.current.mapTileJsonUrl);
        return http.Response(
          jsonEncode({
            'tiles': [
              calls == 1
                  ? 'https://external.test/{z}/{x}/{y}.pbf'
                  : '/api/fork/map/tiles/20261001_120000_pt/{z}/{x}/{y}.pbf',
            ],
          }),
          200,
        );
      });
      await http.runWithClient(() async {
        expect(await MapTiles.template(), Endpoints.current.mapTilesFallback);
        final template = await MapTiles.template();
        expect(Endpoints.current.isOwnMapUrl(template), isTrue);
        expect(
          template,
          contains('/api/fork/map/tiles/20261001_120000_pt/{z}/{x}/{y}.pbf'),
        );
        expect(calls, 2);
      }, () => client);
    },
  );
}
