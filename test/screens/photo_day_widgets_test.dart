import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/widget_screen/photo_day_widgets.dart';

void main() {
  group('какие фото-виджеты показывать', () {
    test('без пары — без группы и «solo»', () {
      expect(PhotoDayWidgets.listed('', null), isTrue);
      expect(PhotoDayWidgets.listed('', ''), isTrue);
      expect(PhotoDayWidgets.listed('', 'solo'), isTrue);
      expect(PhotoDayWidgets.listed('', 'g1'), isFalse);
    });

    test('в паре — свои и ещё не привязанные', () {
      expect(PhotoDayWidgets.listed('g1', 'g1'), isTrue);
      expect(PhotoDayWidgets.listed('g1', null), isTrue);
      expect(PhotoDayWidgets.listed('g1', 'g2'), isFalse);
      expect(PhotoDayWidgets.listed('g1', 'solo'), isFalse);
    });
  });

  group('превью фото-виджета', () {
    test('партнёрский — фото партнёра, без него — превью виджета', () {
      expect(
        PhotoDayWidgets.previewPath(
          isPartner: true,
          widgetUrls: const ['mine'],
          widgetPreviewPath: 'preview',
          partnerSharedPreviewPath: 'partner',
        ),
        'partner',
      );
      expect(
        PhotoDayWidgets.previewPath(
          isPartner: true,
          widgetUrls: const ['mine'],
          widgetPreviewPath: 'preview',
          partnerSharedPreviewPath: null,
        ),
        'preview',
      );
    });

    test('личный — сначала свои ссылки, потом превью виджета', () {
      expect(
        PhotoDayWidgets.previewPath(
          isPartner: false,
          widgetUrls: const ['mine', 'other'],
          widgetPreviewPath: 'preview',
          partnerSharedPreviewPath: 'partner',
        ),
        'mine',
      );
      expect(
        PhotoDayWidgets.previewPath(
          isPartner: false,
          widgetUrls: const [],
          widgetPreviewPath: 'preview',
          partnerSharedPreviewPath: 'partner',
        ),
        'preview',
      );
    });
  });

  group('выбор и имя', () {
    const state = PhotoDayWidgets(
      personalIds: [1, 2],
      partnerIds: [3],
      names: {1: 'Море'},
      selectedPersonal: 1,
      selectedPartner: 3,
    );

    test('выбор меняет только свою карточку', () {
      final personal = state.select(2, partner: false);
      expect(personal.selectedPersonal, 2);
      expect(personal.selectedPartner, 3);

      final partner = state.select(4, partner: true);
      expect(partner.selectedPartner, 4);
      expect(partner.selectedPersonal, 1);
    });

    test('переименование не трогает прежний снимок', () {
      final next = state.renamed(2, 'Горы');
      expect(next.names, {1: 'Море', 2: 'Горы'});
      expect(state.names, {1: 'Море'});
      expect(next.personalIds, [1, 2]);
      expect(next.selectedPersonal, 1);
    });
  });
}
