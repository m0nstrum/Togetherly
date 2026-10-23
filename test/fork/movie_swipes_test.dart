import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/movies/movie_choices.dart';
import 'package:love_app/fork/movies/movie_swipes.dart';
import 'package:love_app/services/movie_search_service.dart';

const group = 'pairaaaaaaaaaaa',
    me = 'aliceaaaaaaaaaa',
    partner = 'bobbbbbbbbbbbbb';
const result = MovieResult(
  id: 10,
  title: 'Matrix',
  year: '1999',
  kind: 'movie',
);
final film = ForkMovieCard.fromResult(result);

class Memory implements ForkMovieRepository {
  final changes = StreamController<void>.broadcast();
  List<ForkMovieChoice?> rows = [];
  bool failing = false;
  Completer<void>? acknowledgement;
  Completer<List<ForkMovieChoice?>>? delayedRead;
  int reads = 0, writes = 0;
  @override
  Future<List<ForkMovieChoice?>> list(String group) async {
    reads++;
    final delayed = delayedRead;
    delayedRead = null;
    return delayed == null ? List.of(rows) : await delayed.future;
  }

  @override
  Future<ForkMovieChoice> propose(String group, ForkMovieCard movie) async {
    final existing = rows.whereType<ForkMovieChoice>().where(
      (row) => row.author == me && row.movie.key == movie.key,
    );
    return existing.isNotEmpty ? existing.first : vote(group, movie, null);
  }

  @override
  Future<ForkMovieChoice> vote(
    String group,
    ForkMovieCard movie,
    bool? value,
  ) async {
    writes++;
    if (acknowledgement != null) await acknowledgement!.future;
    if (failing) throw StateError('offline');
    rows.removeWhere((row) => row?.author == me && row?.movie.key == movie.key);
    final choice = ForkMovieChoice(
      id: 'mine',
      author: me,
      tag: 'opaque',
      movie: movie,
      vote: value,
      created: DateTime.utc(2026),
    );
    rows.insert(0, choice);
    return choice;
  }

  @override
  Stream<void> watch(String group) => changes.stream;
}

void main() {
  late Memory repository;
  setUp(() => repository = Memory());
  tearDown(() async => repository.changes.close());
  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ForkMovieSwipesScreen(
          groupId: group,
          myUid: me,
          partnerUid: partner,
          repository: repository,
          search: (_) async => [result],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ForkMovieChoice proposal() => ForkMovieChoice(
    id: 'mine',
    author: me,
    tag: 'opaque',
    movie: film,
    vote: null,
    created: DateTime.utc(2026),
  );

  testWidgets('card stays until acknowledged; failure keeps it available', (
    tester,
  ) async {
    repository.rows = [proposal()];
    await show(tester);
    repository.acknowledgement = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('movie-yes')));
    await tester.pump();
    expect(find.byKey(const ValueKey('movie-card-title')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('movie-yes')))
          .onPressed,
      isNull,
    );
    repository.failing = true;
    repository.acknowledgement!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movie-card-title')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('movie-yes')))
          .onPressed,
      isNotNull,
    );
    expect(repository.rows.single!.vote, isNull);
  });

  testWidgets('swipe creates a match; undo restores the same candidate', (
    tester,
  ) async {
    repository.rows = [
      proposal(),
      ForkMovieChoice(
        id: 'partner',
        author: partner,
        tag: 'opaque',
        movie: film,
        vote: true,
        created: DateTime.utc(2026),
      ),
    ];
    await show(tester);
    await tester.drag(find.byKey(ValueKey(film.key)), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(repository.rows.first!.vote, isTrue);
    expect(find.byKey(const ValueKey('movie-card-title')), findsNothing);
    final undo = find.byKey(const ValueKey('movie-undo'));
    ScaffoldMessenger.of(tester.element(undo)).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(repository.rows.first!.vote, isNull);
    expect(find.byKey(const ValueKey('movie-card-title')), findsOneWidget);
  });

  testWidgets('a stale refresh cannot roll back an acknowledged choice', (
    tester,
  ) async {
    repository.rows = [proposal()];
    await show(tester);
    final stale = Completer<List<ForkMovieChoice?>>();
    repository.delayedRead = stale;
    repository.changes.add(null);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('movie-yes')));
    await tester.pump();
    expect(repository.rows.first!.vote, isTrue);
    stale.complete([proposal()]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('movie-card-title')), findsNothing);
    expect(repository.reads, greaterThanOrEqualTo(3));
  });

  testWidgets(
    'search remains scrollable with keyboard, narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      try {
        await show(tester, scale: 2);
        await tester.ensureVisible(
          find.byKey(const ValueKey('movies-search-tab')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('movies-search-tab')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pump();
        final field = find.byType(TextField);
        await tester.enterText(field, 'Matrix');
        await tester.tap(find.byIcon(Icons.search_rounded));
        await tester.pumpAndSettle();
        final add = find.byIcon(Icons.add_rounded);
        await tester.scrollUntilVisible(
          add,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(repository.rows, hasLength(1));
        expect(repository.rows.single!.vote, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      }
    },
  );
}
