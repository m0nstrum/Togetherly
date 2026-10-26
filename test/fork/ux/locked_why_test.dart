import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/fork/e2e/locked_why.dart';
import 'package:love_app/fork/ui/chat_hints.dart';

void main() {
  group('почему запись закрыта (UX A9)', () {
    test('причина по состоянию шифрования', () {
      expect(
        forkLockedWhy(started: false, restore: false, hasKey: false),
        ForkLockedWhy.starting,
      );
      expect(
        forkLockedWhy(
          started: false,
          failed: true,
          restore: false,
          hasKey: false,
        ),
        ForkLockedWhy.notStarted,
      );
      expect(
        forkLockedWhy(started: true, restore: true, hasKey: false),
        ForkLockedWhy.needsRestore,
      );
      expect(
        forkLockedWhy(
          started: true,
          restore: false,
          status: PairE2EStatus.waitingPartner,
          hasKey: false,
        ),
        ForkLockedWhy.waitingPartner,
      );
      expect(
        forkLockedWhy(
          started: true,
          restore: false,
          status: PairE2EStatus.waitingKey,
          hasKey: false,
        ),
        ForkLockedWhy.waitingKey,
      );
      expect(
        forkLockedWhy(
          started: true,
          restore: false,
          status: PairE2EStatus.tampered,
          hasKey: true,
        ),
        ForkLockedWhy.tampered,
      );
      expect(
        forkLockedWhy(
          started: true,
          restore: false,
          status: PairE2EStatus.verified,
          hasKey: true,
        ),
        ForkLockedWhy.oldKey,
      );
    });

    test('у каждой причины есть подпись и объяснение', () {
      for (final w in ForkLockedWhy.values) {
        expect(forkLockedShort(w), isNotEmpty);
        expect(forkLockedLong(w).length, greaterThan(40));
      }
    });

    testWidgets('пузырь называет причину, касание — лист с действием', (
      tester,
    ) async {
      ForkE2E.startFailed.value = true;
      addTearDown(() => ForkE2E.startFailed.value = false);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ForkLockedText(color: Colors.black, groupId: 'g1'),
          ),
        ),
      );
      expect(
        find.textContaining(
          forkLockedShort(ForkLockedWhy.notStarted).toLowerCase(),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(ForkLockedText));
      await tester.pumpAndSettle();
      expect(
        find.text(forkLockedLong(ForkLockedWhy.notStarted)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    test('пока шифрование поднимается, очередь не пугаем', () {
      ForkE2E.startFailed.value = false;
      expect(forkSealBlocked('g1'), isFalse);
      ForkE2E.startFailed.value = true;
      expect(forkSealBlocked('g1'), isTrue);
      expect(forkSealBlocked(''), isFalse);
      ForkE2E.startFailed.value = false;
    });
  });
}
