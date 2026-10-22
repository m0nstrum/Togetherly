// fork: тумблеры уведомлений действуют сразу (UX G11).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/push/notif_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('выбор на телефоне важнее устаревшей записи профиля', () async {
    SharedPreferences.resetStatic();
    ForkNotifPrefs.debugUse(null);
    SharedPreferences.setMockInitialValues({'notif_chat': false});
    await ForkNotifPrefs.refresh();
    expect(ForkNotifPrefs.enabled('notif_chat', true), isFalse);
  });

  test('тумблер не трогали — берём профиль, иначе включено', () async {
    SharedPreferences.resetStatic();
    ForkNotifPrefs.debugUse(null);
    SharedPreferences.setMockInitialValues({});
    await ForkNotifPrefs.refresh();
    expect(ForkNotifPrefs.enabled('notif_mood', false), isFalse);
    expect(ForkNotifPrefs.enabled('notif_gifts', null), isTrue);
  });

  test('refresh подхватывает свежее значение', () async {
    SharedPreferences.resetStatic();
    ForkNotifPrefs.debugUse(null);
    SharedPreferences.setMockInitialValues({});
    await ForkNotifPrefs.refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_gifts', false);
    expect(ForkNotifPrefs.enabled('notif_gifts', true), isFalse);
  });
}
