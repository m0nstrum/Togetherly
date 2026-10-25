import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/movie_search_service.dart';
import '../../utils/safe_launch.dart';
import '../ui/feedback.dart';
import 'movie_choices.dart';

class ForkMovieSwipesScreen extends StatefulWidget {
  const ForkMovieSwipesScreen({
    super.key,
    required this.groupId,
    required this.myUid,
    required this.partnerUid,
    this.repository,
    this.search,
  });
  final String groupId, myUid, partnerUid;
  final ForkMovieRepository? repository;
  final Future<List<MovieResult>> Function(String)? search;
  @override
  State<ForkMovieSwipesScreen> createState() => _ForkMovieSwipesScreenState();
}

class _ForkMovieSwipesScreenState extends State<ForkMovieSwipesScreen>
    with SingleTickerProviderStateMixin {
  late final repo = widget.repository ?? ForkMovieChoices.instance;
  final _query = TextEditingController();
  StreamSubscription<void>? _events;
  List<ForkMovieChoice?> _rows = [];
  List<MovieResult> _results = [];
  Future<void>? _refreshing;
  bool _again = false, _loading = false, _failed = false, _busy = false;
  bool _searching = false, _searchFailed = false, _searched = false;
  final _adding = <String>{};
  ForkMovieCard? _undo;
  double _drag = 0;
  int _writeRevision = 0;
  bool _readOnce = false;
  Set<String> _knownMatches = {};
  ForkMoviePicks get _picks => ForkMoviePicks(
    _rows.whereType<ForkMovieChoice>().toList(),
    widget.myUid,
    widget.partnerUid,
  );
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _events = repo
        .watch(widget.groupId)
        .listen(
          (_) => unawaited(_refresh()),
          onError: (Object _) {
            if (mounted) setState(() => _failed = true);
          },
        );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _query.dispose();
    _fly.dispose();
    super.dispose();
  }

  // D4: карточка идёт за пальцем, улетает по свайпу и мягко возвращается.
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  Future<void> _animateDrag(double to) async {
    final tween = Tween<double>(
      begin: _drag,
      end: to,
    ).animate(CurvedAnimation(parent: _fly, curve: Curves.easeOutCubic));
    void tick() {
      if (mounted) setState(() => _drag = tween.value);
    }

    _fly.addListener(tick);
    try {
      await _fly.forward(from: 0).orCancel;
    } on TickerCanceled {
      // экран закрыли посреди полёта
    } finally {
      _fly.removeListener(tick);
    }
  }

  /// Палец отпустил карточку: далеко или быстро — голос, иначе назад.
  Future<void> _release(
    ForkMovieCard movie,
    double width,
    double velocity,
  ) async {
    final far = _drag.abs() >= math.min(110.0, width * 0.28);
    final fast = velocity.abs() > 700 && velocity.sign == _drag.sign;
    if (!far && !fast) {
      await _animateDrag(0);
      return;
    }
    final yes = _drag > 0;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    await _animateDrag((yes ? 1 : -1) * width * 1.3);
    if (mounted) await _vote(movie, yes, swiped: true);
  }

  Future<void> _refresh() {
    if (_refreshing != null) {
      _again = true;
      return _refreshing!;
    }
    final future = _read();
    _refreshing = future;
    unawaited(
      future.then((_) {
        if (identical(_refreshing, future)) _refreshing = null;
      }),
    );
    return future;
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _loading = true);
    do {
      _again = false;
      try {
        final revision = _writeRevision;
        final rows = await repo.list(widget.groupId);
        if (revision != _writeRevision) {
          _again = true;
          continue;
        }
        if (mounted) {
          setState(() {
            _rows = rows;
            _failed = false;
          });
          _announceMatches();
        }
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
    } while (_again && mounted);
    if (mounted) setState(() => _loading = false);
  }

  void _accept(ForkMovieChoice saved) {
    _writeRevision++;
    setState(() {
      _rows.removeWhere(
        (choice) =>
            choice?.id == saved.id ||
            (choice?.author == saved.author &&
                choice?.movie.key == saved.movie.key),
      );
      _rows.insert(0, saved);
      _drag = 0;
    });
    _announceMatches();
  }

  void _announceMatches() {
    final matches = _picks.matches;
    final fresh = matches
        .where((movie) => !_knownMatches.contains(movie.key))
        .toList();
    _knownMatches = matches.map((movie) => movie.key).toSet();
    if (_readOnce && fresh.isNotEmpty) {
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      ForkNotice.info(
        context,
        ruEn(
          'Совпало: ${fresh.first.title}',
          'It’s a match: ${fresh.first.title}',
        ),
      );
    }
    _readOnce = true;
  }

  Future<void> _vote(
    ForkMovieCard movie,
    bool? value, {
    bool swiped = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      // Улетевшая карточка ждёт ответа за краем экрана, а не прыгает назад.
      if (!swiped) _drag = 0;
    });
    try {
      final saved = await repo.vote(widget.groupId, movie, value);
      if (!mounted) return;
      _accept(saved);
      setState(() => _undo = value == null ? null : movie);
    } catch (error) {
      if (mounted) {
        unawaited(_animateDrag(0));
        ForkNotice.error(context, error, retry: () => _vote(movie, value));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(MovieResult result) async {
    final movie = ForkMovieCard.fromResult(result);
    if (_adding.contains(movie.key)) return;
    setState(() => _adding.add(movie.key));
    try {
      final saved = await repo.propose(widget.groupId, movie);
      if (mounted) {
        _accept(saved);
        ForkNotice.info(context, ruEn('В общей колоде', 'In your shared deck'));
      }
    } catch (error) {
      if (mounted) {
        ForkNotice.error(context, error, retry: () => _propose(result));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(movie.key));
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (_searching || query.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchFailed = false;
      _searched = false;
      _results = [];
    });
    try {
      final results = await (widget.search ?? MovieSearchService.search)(query);
      if (mounted && _query.text.trim() == query) {
        setState(() {
          _results = results;
          _searched = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _info(ForkMovieCard movie) async {
    if (!await safeLaunchString(movie.info) && mounted) {
      ForkNotice.failure(context, ForkFailure.unknown);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: (MediaQuery.textScalerOf(context).scale(20) * 2.4 + 12)
            .clamp(56, double.infinity),
        title: Text(
          ruEn('Что посмотрим?', 'What shall we watch?'),
          maxLines: 2,
        ),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              key: const ValueKey('movies-deck-tab'),
              text: ruEn('Выбор', 'Swipe'),
            ),
            Tab(
              key: const ValueKey('movies-search-tab'),
              text: ruEn('Добавить', 'Add films'),
            ),
            Tab(
              text: ruEn(
                'Совпало · ${_picks.matches.length}',
                'Matches · ${_picks.matches.length}',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: TabBarView(children: [_deck(), _find(), _matches()])),
        ],
      ),
    ),
  );
  Widget _status() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_failed)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              ruEn(
                'Не удалось обновить колоду.',
                'Could not refresh the deck.',
              ),
            ),
            TextButton(
              onPressed: _refresh,
              child: Text(ruEn('Повторить', 'Retry')),
            ),
          ],
        ),
      if (_rows.any((row) => row == null))
        Text(
          ruEn(
            'Часть карточек закрыта. Нужны ключи пары с другого устройства или из бэкапа.',
            'Some cards are locked. Pair keys from another device or a backup are required.',
          ),
        ),
    ],
  );
  Widget _deck() {
    final pending = _picks.pending;
    final movie = pending.isEmpty ? null : pending.first;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _status(),
            Text(
              ruEn(
                'Вправо — хочу смотреть, влево — не сейчас. Выбор увидите в совпадениях, когда он общий.',
                'Swipe right to watch, left for not now. Two yes votes appear in Matches.',
              ),
            ),
            const SizedBox(height: 12),
            if (movie == null && !_loading && !_failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  _picks.all.isEmpty
                      ? ruEn(
                          'Добавьте фильмы в общую колоду на вкладке «Добавить».',
                          'Add films to your shared deck in the Add films tab.',
                        )
                      : ruEn(
                          'Вы оценили все карточки. Общие «да» будут на вкладке «Совпало».',
                          'You rated every card. Mutual yes votes appear in Matches.',
                        ),
                ),
              ),
            if (movie != null) ...[
              LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  key: ValueKey(movie.key),
                  onHorizontalDragStart: _busy ? null : (_) => _fly.stop(),
                  onHorizontalDragUpdate: _busy
                      ? null
                      : (event) => setState(() => _drag += event.delta.dx),
                  onHorizontalDragCancel: () => unawaited(_animateDrag(0)),
                  onHorizontalDragEnd: _busy
                      ? null
                      : (end) => unawaited(
                          _release(
                            movie,
                            box.maxWidth,
                            end.primaryVelocity ?? 0,
                          ),
                        ),
                  child: Transform.translate(
                    offset: Offset(_drag, _drag.abs() * 0.06),
                    child: Transform.rotate(
                      angle: (_drag / math.max(1, box.maxWidth)) * 0.35,
                      child: Stack(
                        children: [
                          _card(movie),
                          if (_drag.abs() > 24)
                            Positioned(
                              top: 20,
                              left: _drag > 0 ? 20 : null,
                              right: _drag < 0 ? 20 : null,
                              child: Opacity(
                                opacity: ((_drag.abs() - 24) / 80).clamp(
                                  0.0,
                                  1.0,
                                ),
                                child: _verdict(_drag > 0),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('movie-no'),
                    onPressed: _busy ? null : () => _vote(movie, false),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(ruEn('Не сейчас', 'Not now')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('movie-yes'),
                    onPressed: _busy ? null : () => _vote(movie, true),
                    icon: const Icon(Icons.favorite_rounded),
                    label: Text(ruEn('Хочу смотреть', 'Want to watch')),
                  ),
                ],
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            TextButton.icon(
              key: const ValueKey('movie-undo'),
              onPressed: _busy || _undo == null
                  ? null
                  : () => _vote(_undo!, null),
              icon: const Icon(Icons.undo_rounded),
              label: Text(ruEn('Отменить последний выбор', 'Undo last choice')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ForkMovieCard movie) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (movie.poster != null)
          SizedBox(
            height: 260,
            child: _poster(movie.poster, fit: BoxFit.cover),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                movie.title,
                key: const ValueKey('movie-card-title'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (movie.original.isNotEmpty && movie.original != movie.title)
                Text(movie.original),
              Text(
                [
                  movie.year,
                  movie.genres,
                ].where((value) => value.isNotEmpty).join(' · '),
              ),
              if (movie.description.isNotEmpty)
                Text(
                  movie.description,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              if (movie.info != null)
                TextButton(
                  onPressed: () => _info(movie),
                  child: Text(ruEn('О фильме', 'About the film')),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Подсказка на карточке, пока её тянут: куда ляжет голос.
  Widget _verdict(bool yes) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: yes ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        yes ? ruEn('Хочу', 'Want it') : ruEn('Не сейчас', 'Not now'),
        style: TextStyle(
          color: yes ? cs.onPrimary : cs.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _poster(String? url, {BoxFit fit = BoxFit.cover}) {
    final cs = Theme.of(context).colorScheme;
    final empty = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, size: 40, color: cs.onSurfaceVariant),
      ),
    );
    if (url == null || url.isEmpty) return empty;
    return Image.network(url, fit: fit, errorBuilder: (_, _, _) => empty);
  }

  /// D3: плитка фильма — обложка, название, год; [action] — в углу обложки.
  Widget _tile({
    required String title,
    required String year,
    required String? poster,
    required double width,
    Widget? action,
    VoidCallback? onTap,
    Widget? badge,
  }) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _poster(poster),
                    if (badge != null)
                      Positioned(left: 8, top: 8, child: badge),
                    if (action != null)
                      Positioned(right: 4, bottom: 4, child: action),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall,
            ),
            if (year.isNotEmpty) Text(year, style: text.bodySmall),
          ],
        ),
      ),
    );
  }

  /// Плитки в ряд по ширине: от двух на узком экране до пяти на планшете.
  Widget _grid(List<Widget Function(double width)> tiles) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final columns = (box.maxWidth / 160).floor().clamp(2, 5);
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 16,
        children: [for (final tile in tiles) tile(width)],
      );
    },
  );

  Widget _find() => ListView(
    key: const ValueKey('movies-search-list'),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _status(),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: ruEn(
              'Название фильма или сериала',
              'Film or series title',
            ),
            suffixIcon: IconButton(
              tooltip: ruEn('Найти', 'Search'),
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
      ),
      if (_searching) const LinearProgressIndicator(),
      if (_searchFailed)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                ruEn(
                  'Поиск недоступен. Проверьте связь и попробуйте позже.',
                  'Search is unavailable. Check your connection and try later.',
                ),
              ),
              TextButton(
                onPressed: _search,
                child: Text(ruEn('Повторить', 'Retry')),
              ),
            ],
          ),
        ),
      if (_searched && _results.isEmpty)
        Text(ruEn('Ничего не найдено', 'No films found')),
      if (_results.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: _grid([
            for (final result in _results)
              (width) {
                final key = ForkMovieCard.fromResult(result).key;
                final inDeck = _picks.all.any((m) => m.key == key);
                return _tile(
                  title: result.title,
                  year: result.year ?? '',
                  poster: result.posterUrl,
                  width: width,
                  onTap: inDeck || _adding.contains(key)
                      ? null
                      : () => _propose(result),
                  action: IconButton.filled(
                    tooltip: inDeck
                        ? ruEn('Уже в колоде', 'Already in the deck')
                        : ruEn('Добавить в общую колоду', 'Add to shared deck'),
                    onPressed: inDeck || _adding.contains(key)
                        ? null
                        : () => _propose(result),
                    icon: Icon(
                      inDeck ? Icons.check_rounded : Icons.add_rounded,
                    ),
                  ),
                );
              },
          ]),
        ),
    ],
  );
  Widget _matches() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _status(),
        if (_picks.matches.isEmpty && !_loading && !_failed)
          Text(
            ruEn(
              'Пока нет общих «Хочу смотреть». Выбирайте фильмы независимо друг от друга.',
              'No mutual yes votes yet. Choose films independently.',
            ),
          ),
        if (_picks.matches.isNotEmpty)
          _grid([
            for (final movie in _picks.matches)
              (width) => _tile(
                title: movie.title,
                year: movie.year,
                poster: movie.poster,
                width: width,
                onTap: movie.info == null ? null : () => _info(movie),
                badge: CircleAvatar(
                  radius: 14,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ]),
      ],
    ),
  );
}
