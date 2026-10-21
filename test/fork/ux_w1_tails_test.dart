import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';
import 'package:love_app/fork/ui/feedback.dart';
import 'package:love_app/models/chest.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  test('A14: 401 распознаётся как «сессия кончилась»', () {
    expect(ForkFailure.of(ClientException(statusCode: 401)), ForkFailure.session);
    expect(ForkFailure.of(ClientException(statusCode: 500)), ForkFailure.unknown);
  });

  test('M11: запасная таблица шансов без Плюса не содержит его призов', () {
    final odds = fallbackChestOdds(withPlus: false);
    expect(
      odds.where((p) => p.kind == ChestPrizeKind.plus || p.kind == ChestPrizeKind.plusTrial),
      isEmpty,
    );
  });

  test('allFree включён в сборке форка', () {
    expect(ForkFlags.allFree, isTrue);
  });
}
