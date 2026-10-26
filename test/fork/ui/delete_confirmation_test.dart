import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/models/pair_data.dart';
import 'package:love_app/screens/home/widgets/relationship_type_dialog.dart';
import 'package:love_app/screens/miss_you_screen.dart';
import 'package:love_app/services/custom_wishes_store.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';

class _Pair extends PairData {
  int deleted = 0;
  @override
  RelationshipType get relationshipType => RelationshipType.custom;
  @override
  String get relationshipLabel => 'Current';
  @override
  List<Map<String, String>> get customRelationshipTypes => [
    {'id': 'a', 'label': 'Current', 'emoji': '❤️'},
    {'id': 'b', 'label': 'Other', 'emoji': '⭐'},
  ];
  @override
  Future<void> deleteCustomRelationshipType(String id) async {
    deleted++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'phrase menu is separate from sending; cancel preserves the phrase',
    (t) async {
      SharedPreferences.setMockInitialValues({
        CustomWishesStore.prefsKey: ['Coffee please'],
      });
      await t.pumpWidget(
        MaterialApp(
          home: MissYouScreen(
            theme: AppThemes.pink,
            groupId: '',
            myUid: 'me',
            partnerUid: '',
            partnerName: '',
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      final menu = find.byType(PopupMenuButton<String>);
      await t.ensureVisible(menu);
      expect(t.getSize(menu).width, greaterThanOrEqualTo(48));
      await t.tap(menu);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.textContaining(RegExp('Удалить фразу|Delete phrase')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text(LocaleService.current.cancel));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(await CustomWishesStore.load(), ['Coffee please']);
      await t.tap(menu);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.textContaining(RegExp('Удалить фразу|Delete phrase')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text(LocaleService.current.delete));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(await CustomWishesStore.load(), isEmpty);
    },
  );

  testWidgets(
    'current relationship type cannot be deleted; other type asks first',
    (t) async {
      final pair = _Pair();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => showRelationshipTypeSheet(
                  ctx,
                  pair: pair,
                  theme: AppThemes.pink,
                  onChanged: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      final buttons = find.widgetWithIcon(
        IconButton,
        Icons.delete_outline_rounded,
      );
      expect(t.widget<IconButton>(buttons.first).onPressed, isNull);
      await t.ensureVisible(buttons.last);
      await t.tap(buttons.last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(pair.deleted, 0);
      await t.tap(find.text(LocaleService.current.cancel));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(pair.deleted, 0);
      await t.tap(buttons.last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text(LocaleService.current.delete));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(pair.deleted, 1);
    },
  );
}
