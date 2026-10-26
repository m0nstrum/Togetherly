// Кнопка камеры на аватаре в шапке профиля не нажималась (обращение 216,
// 30.09.2026: «нажимаю на кнопку и вообще ни в какую»). Аватар свисает с
// баннера на 40 точек, камера целиком сидела в этой свисающей части, а
// Flutter не пропускает нажатия к детям за границей Stack. Та же беда была
// у нижней половины аватара: по ней не открывался магазин рамок.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/profile/profile_hero.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  setUp(() => LocaleService.instance.setLanguage(AppLanguage.ru));

  Future<(List<String>, Finder)> pump(WidgetTester tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ProfileHero(
                cs: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7E8B)),
                uid: 'u1',
                avatarUrl: '',
                name: 'сифон',
                bannerUrl: '',
                subtitle: 'вместе 688 дней',
                onTapAvatar: () => taps.add('camera'),
                onTapFrame: () => taps.add('frame'),
                onEdit: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return (taps, find.byIcon(Icons.photo_camera_rounded));
  }

  testWidgets('кнопка камеры меняет фото', (tester) async {
    final (taps, camera) = await pump(tester);
    expect(camera, findsOneWidget);
    await tester.tap(camera);
    expect(taps, ['camera']);
  });

  // fork: N4 — тап по самому фото правит фото и имя, рамки — своя кнопка.
  testWidgets('нижняя половина аватара открывает правку фото', (tester) async {
    final (taps, camera) = await pump(tester);
    // Точка левее камеры, в свисающей части аватара.
    final c = tester.getCenter(camera);
    await tester.tapAt(c.translate(-45, -8));
    expect(taps, ['camera']);
  });

  testWidgets('рамки открываются отдельной кнопкой', (tester) async {
    final (taps, _) = await pump(tester);
    await tester.tap(find.byIcon(Icons.filter_frames_rounded));
    expect(taps, ['frame']);
  });
}
