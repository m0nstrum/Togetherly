@Tags(['fork-runtime'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/gifts/gift_shop_screen.dart';
import 'package:love_app/widgets/common/coin_image.dart';

void main() {
  testWidgets(
    'available free gift has one action and returns the free grant choice',
    (t) async {
      bool? choice;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  choice = await showModalBottomSheet<bool>(
                    context: ctx,
                    builder: (_) => const GiftPaySheet(
                      art: Icon(Icons.favorite),
                      title: 'Gift',
                      price: 25,
                      coins: 100,
                      adAllowed: true,
                      plus: true,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(CoinImage), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      await t.tap(find.textContaining(RegExp('Подарить|Give gift')));
      await t.pumpAndSettle();
      expect(choice, isTrue, reason: 'free/Plus branch, no coin debit');
    },
  );

  testWidgets('unavailable free allowance keeps the priced fallback', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GiftPaySheet(
            art: Icon(Icons.favorite),
            title: 'Gift',
            price: 25,
            coins: 100,
            adAllowed: false,
            plus: true,
          ),
        ),
      ),
    );
    expect(find.byType(CoinImage), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.textContaining(RegExp('Подарить|Give gift')), findsNothing);
  });
}
