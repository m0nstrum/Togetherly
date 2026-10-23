@Tags(['fork-runtime'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';
import 'package:love_app/services/update_service.dart';

void main() {
  test('fork does not consult the upstream version manifest or platform plugins', () async {
    expect(ForkFlags.upstreamUpdates, isFalse);
    // No platform mocks or HTTP setup: it must return before either is used.
    expect(await UpdateService.checkForUpdate(), isNull);
  });
}
