// fork: вход в аккаунт площадки для «Лент вдвоём».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/reels/platform_account.dart';
import 'package:love_app/models/reels_source.dart';

void main() {
  test('Shorts без входа, остальные — со страницей площадки', () {
    expect(PlatformAccount.of(ReelsSource.shorts), isNull);
    for (final s in ReelsSource.values.where((s) => s != ReelsSource.shorts)) {
      final a = PlatformAccount.of(s)!;
      expect(a.login, startsWith('https://'));
      expect(a.domains, isNotEmpty);
    }
  });

  testWidgets('строка: Shorts объясняет, TikTok предлагает войти', (
    tester,
  ) async {
    Future<void> show(ReelsSource s) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ForkReelsAccountRow(source: s)),
      ),
    );
    await show(ReelsSource.shorts);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('Google'), findsOneWidget);

    await show(ReelsSource.tiktok);
    await tester.pump();
    expect(find.byType(TextButton), findsWidgets);
  });
}
