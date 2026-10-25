import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_due.dart';
import 'package:love_app/widgets/wishes/wish_details_sheet.dart';
import 'package:love_app/widgets/wishes/wish_due_picker.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.light()),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('«Когда»: когда-нибудь, месяц и сброс', (tester) async {
    var due = WishDue.none;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (_, set) => WishDuePicker(
        value: due,
        scheme: const ColorScheme.light(),
        ru: true,
        onChanged: (v) => set(() => due = v),
      ),
    )));

    await tester.tap(find.byKey(const Key('wish-due-someday')));
    await tester.pump();
    expect(due, WishDue.someday);

    await tester.tap(find.byKey(const Key('wish-due-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wish-month-12')));
    await tester.pumpAndSettle();
    expect(due.kind, WishDueKind.month);
    expect(due.month, 12);
    expect(due.year, DateTime.now().year);

    await tester.tap(find.byKey(const Key('wish-due-none')));
    await tester.pump();
    expect(due, WishDue.none);
  });

  testWidgets('чужое желание: срок виден, «я тоже хочу» переключается',
      (tester) async {
    var calls = 0;
    final wish = Wish(
      id: 'w',
      title: 'Каток',
      authorUid: 'a',
      due: WishDue.someday,
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(host(WishDetailsSheet(
      wish: wish,
      authorName: 'Аня',
      onAlso: () async => calls++,
    )));

    expect(find.text(wishDueLabel(WishDue.someday)), findsOneWidget);
    final chip = find.byKey(const Key('wish-details-also'));
    expect(tester.widget<FilterChip>(chip).selected, isFalse);
    await tester.tap(chip);
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
  });
}
