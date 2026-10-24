import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pocketbase_service.dart';

void main() {
  test('logout works before any UI binding or producer has started', () {
    expect(() => PocketBaseService().signOut(), returnsNormally);
  });
}
