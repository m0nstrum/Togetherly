import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:love_app/fork/widget_pin_confirmation.dart';

void main() {
  test(
    'dialog/cancel/existing widget never grant success; new matching ID does once',
    () async {
      var list = [HomeWidgetInfo(androidWidgetId: 1, androidClassName: 'a')];
      var awards = 0;
      final tracker = ForkWidgetPinConfirmation(
        installed: () async => list,
        confirmed: () async {
          awards++;
        },
      );
      await tracker.request('a', () async {});
      await tracker.check();
      expect(awards, 0);
      list.add(HomeWidgetInfo(androidWidgetId: 2, androidClassName: 'b'));
      await tracker.check();
      expect(awards, 0);
      list.add(HomeWidgetInfo(androidWidgetId: 3, androidClassName: 'a'));
      await tracker.check();
      await tracker.check();
      expect(awards, 1);
      expect(tracker.pending, isFalse);
    },
  );

  test('failed request does not leave a confirmation to award later', () async {
    final tracker = ForkWidgetPinConfirmation(
      installed: () async => [],
      confirmed: () async => fail('must not confirm'),
    );
    await expectLater(
      tracker.request('a', () async => throw StateError('failed')),
      throwsStateError,
    );
    expect(tracker.pending, isFalse);
  });
}
