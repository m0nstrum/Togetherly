import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/features/pet_home/pet_home_model.dart';
import 'package:love_app/features/pet_home/pet_home_repository.dart';
import 'package:love_app/features/pet_home/pet_home_screen.dart';

class MemoryHome extends PetHomeRepository {
  MemoryHome()
    : super(
        pb: PocketBase('https://example.test'),
        codec: () async => null,
        uid: () => 'alice',
      );
  PetHome home = PetHome();
  int revision = 0;
  @override
  Future<PetHomeSnapshot> load(String group) async =>
      PetHomeSnapshot(revision, home.copy());
  @override
  Future<PetHomeSnapshot> change(
    String group,
    void Function(PetHome) mutate, {
    int xp = 0,
    String? operation,
  }) async {
    final copy = home.copy()..creditActivity(xp);
    mutate(copy);
    home = copy;
    return PetHomeSnapshot(++revision, home.copy());
  }
}

void main() {
  setUpAll(() async {
    final onest = FontLoader('Onest')
      ..addFont(rootBundle.load('assets/fonts/Onest.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await onest.load();
    await icons.load();
  });

  Widget screen(MemoryHome repo, {bool family = true, VoidCallback? gallery}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'Onest'),
        home: PetHomeScreen(
          groupId: 'group',
          uid: 'alice',
          names: const {'alice': 'Саша', 'bob': 'Женя'},
          family: family,
          repository: repo,
          pet: Image.asset('assets/images/mascots/lulu.webp'),
          openGallery: gallery ?? () {},
          sharedXp: () => 0,
        ),
      );

  testWidgets('care persists, purchases equip, chosen roles change speech', (
    tester,
  ) async {
    final repo = MemoryHome();
    await tester.pumpWidget(screen(repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Feed'));
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crunchies'));
    await tester.pumpAndSettle();
    expect(repo.home.care['feed'], 1);
    expect(repo.home.balance, 45);
    await tester.ensureVisible(find.text('Furnish'));
    await tester.tap(find.text('Furnish'));
    await tester.pumpAndSettle();
    expect(find.text('Make it home'), findsOneWidget);
    await tester.ensureVisible(find.text('Buy').first);
    await tester.tap(find.text('Buy').first);
    await tester.pumpAndSettle();
    expect(repo.home.owned, contains('armchair'));
    expect(repo.home.equipped[PetSlot.seat], 'armchair');
    expect(repo.home.balance, 29);
    await tester.tap(find.byTooltip('Pet names for you'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mom'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.home.roles['alice']!.kind, 'mom');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('narrow screen, large type, keyboard and friends remain usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryHome();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: screen(repo, family: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Pet names for you'));
    await tester.pumpAndSettle();
    expect(find.text('Mom'), findsNothing);
    expect(find.text('Dad'), findsNothing);
    await tester.ensureVisible(find.text('Custom name'));
    await tester.tap(find.text('Custom name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Лис');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.home.roles['alice']!.custom, 'Лис');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('actual layered room preview and accessible action targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryHome();
    for (final id in ['monstera', 'daisies', 'frame']) {
      repo.home.owned.add(id);
      repo.home.equipped[petItem(id).slot] = id;
    }
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: screen(repo)));
    await tester.pumpAndSettle();
    for (final label in ['Feed', 'Wash', 'Play', 'Stroke', 'Furnish']) {
      final size = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(TextButton))
            .first,
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    if (const bool.fromEnvironment('PET_HOME_PREVIEW')) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '/tmp/pet-home-screen.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
