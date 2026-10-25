import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/fork/ui/chat_identity_layout.dart';
import 'package:love_app/fork/watch/room_live.dart';
import 'package:love_app/fork/watch/room_shell.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/models/connection.dart';
import 'package:love_app/screens/home/home_header.dart';
import 'package:love_app/screens/welcome_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/theme_scope.dart';

Widget host(Widget child, double scale) => ThemeScope(
  theme: AppThemes.pink,
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [2.0, 3.0]) {
    testWidgets('welcome at 360x640 and $scale has reachable actions', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(WelcomeScreen(userData: UserData()), scale));
      await t.pump();
      final next = find.text(LocaleService.current.welcomeNext);
      await t.ensureVisible(next);
      await t.pump();
      expect(t.getCenter(next).dy, lessThan(640));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('room at 360 and scale 2 keeps video actions in a menu', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final live = ForkRoomLive(partnerName: () => 'Very long partner name');
    live.handle({
      't': 'source',
      'kind': 'youtube',
      'url': 'u',
      'label': 'Long video title',
    });
    live.handle({'t': 'manual', 'on': true});
    var fullscreen = 0;
    await t.pumpWidget(
      host(
        Column(
          children: [
            ForkRoomTopBar(
              partnerName: 'Very long partner name',
              partnerHere: false,
              onBack: () {},
              onInvite: () {},
              invited: false,
              voice: null,
              onCall: () {},
              onShare: () {},
              onCopy: () {},
            ),
            ForkNowPlaying(
              live: live,
              onPick: () {},
              onToggle: () {},
              onTogether: () {},
              onPauseBoth: () {},
              onFullscreen: () => fullscreen++,
            ),
          ],
        ),
        2,
      ),
    );
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    await t.tap(find.byType(PopupMenuButton<String>).last);
    await t.pumpAndSettle();
    await t.tap(find.textContaining(RegExp('Во весь экран|Full screen')));
    await t.pumpAndSettle();
    expect(fullscreen, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('paired home header at 360 and scale 2 fits its controls', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(
        HomeHeader(
          theme: AppThemes.pink,
          isPaired: true,
          myAvatarUrl: '',
          myDisplayName: 'A',
          partners: const [GroupMember(uid: 'p', name: 'P', avatar: '')],
          myMood: const MemberMood(),
          moodOf: (_) => const MemberMood(),
          statusBadgeText: 'Very long relationship',
          statusBadgeEmoji: '',
          pairId: '',
        ),
        2,
      ),
    );
    await t.pump();
    expect(t.takeException(), isNull);
  });

  for (final width in [100.0, 200.0]) {
    testWidgets(
      'chat identity at width $width keeps long status in its own line',
      (t) async {
        await t.pumpWidget(
          host(
            Center(
              child: SizedBox(
                width: width,
                child: ForkChatIdentityLayout(
                  dot: const Icon(Icons.circle, size: 8),
                  name: const Text(
                    'Very long partner name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16),
                  ),
                  status: const Text(
                    'Typing a long message…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5),
                  ),
                  battery: const Text('42%', key: Key('battery')),
                ),
              ),
            ),
            2,
          ),
        );
        expect(
          find.byKey(const Key('battery')),
          width < 180 ? findsNothing : findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
