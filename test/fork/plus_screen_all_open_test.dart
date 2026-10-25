// T6: в Tethered витрины «Плюс» нет — экран говорит, что всё открыто.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';
import 'package:love_app/screens/plus_screen.dart';

void main() {
  testWidgets('PlusScreen без витрины, когда всё открыто', (tester) async {
    if (!ForkFlags.allFree) return; // сборка апстрима: витрина своя
    await tester.pumpWidget(MaterialApp(
      home: PlusScreen(scheme: ColorScheme.fromSeed(seedColor: Colors.pink)),
    ));
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    expect(find.textContaining('₽'), findsNothing);
  });
}
