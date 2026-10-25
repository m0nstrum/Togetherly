import 'dart:async';
import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/reels/reel_save.dart';
import '../../utils/safe_launch.dart';
import '../../utils/video_link_thumb.dart';
import '../ui/feedback.dart';
import 'matches.dart';

class ForkReelsMatchesScreen extends StatefulWidget {
  const ForkReelsMatchesScreen({
    super.key,
    required this.groupId,
    this.load,
    this.keep,
  });
  final String groupId;
  final Future<List<ForkReelMatch>> Function()? load;

  /// Сохранить ролик в воспоминания (для тестов); по умолчанию — [ReelSave.save].
  final Future<bool> Function({required String groupId, required String key})?
  keep;
  @override
  State<ForkReelsMatchesScreen> createState() => _ForkReelsMatchesScreenState();
}

class _ForkReelsMatchesScreenState extends State<ForkReelsMatchesScreen> {
  List<ForkReelMatch> _items = [];
  bool _loading = false, _failed = false;
  final _deleting = <String>{};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items =
          await (widget.load?.call() ??
              ForkReelsMatches.instance.list(widget.groupId));
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ForkReelMatch match) async {
    if (!await safeLaunchString(match.link!.url) && mounted) {
      ForkNotice.failure(
        context,
        ForkFailure.unknown,
        what: ruEn('Открыть ролик', 'Open clip'),
        retry: () => _open(match),
      );
    }
  }

  Future<void> _delete(ForkReelMatch match) async {
    if (_deleting.contains(match.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ruEn('Удалить совпадение?', 'Delete this match?')),
        content: Text(
          ruEn(
            'Ролик исчезнет из списка у вас обоих.',
            'The clip will disappear from both partners’ lists.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ruEn('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ruEn('Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(match.id));
    try {
      await ForkReelsMatches.instance.remove(match.id);
      if (mounted) {
        setState(() => _items.removeWhere((entry) => entry.id == match.id));
      }
    } catch (error) {
      if (mounted) ForkNotice.failure(context, ForkFailure.of(error));
    } finally {
      if (mounted) setState(() => _deleting.remove(match.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(ruEn('Совпадения в ленте', 'Reel matches'))),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ruEn(
              'Ролики, на которые вы оба отреагировали одинаково.',
              'Clips you both reacted to in the same way.',
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_failed) ...[
            Text(
              ruEn(
                'Не удалось загрузить совпадения.',
                'Could not load matches.',
              ),
            ),
            TextButton(
              onPressed: _load,
              child: Text(ruEn('Повторить', 'Retry')),
            ),
          ],
          if (!_loading && !_failed && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                ruEn(
                  'Пока нет совпадений. Они появятся после общих реакций в ленте.',
                  'No matches yet. React together in the reel feed to save one.',
                ),
              ),
            ),
          for (final item in _items)
            item.locked ? _lockedCard() : _matchCard(item),
        ],
      ),
    ),
  );

  Widget _lockedCard() => Card(
    child: ListTile(
      leading: const Icon(Icons.lock_outline_rounded),
      title: Text(ruEn('Ролик закрыт', 'Clip is locked')),
      subtitle: Text(
        ruEn(
          'Нужны ключи пары с другого устройства или из бэкапа.',
          'Pair keys from another device or a backup are required.',
        ),
      ),
    ),
  );

  /// D5: совпадение — карточкой с кадром ролика, общей реакцией и делом:
  /// смотреть, сохранить в воспоминания, убрать.
  Widget _matchCard(ForkReelMatch item) {
    final link = item.link!;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final thumb = link.knownThumb ?? videoLinkThumb(link.url);
    final empty = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.smart_display_rounded,
          size: 48,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
    final when = item.at == null
        ? ''
        : MaterialLocalizations.of(
            context,
          ).formatCompactDate(item.at!.toLocal());
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _open(item),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb.isEmpty)
                    empty
                  else
                    Image.network(
                      thumb,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => empty,
                    ),
                  Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      size: 56,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (item.reaction.isNotEmpty)
                    Positioned(
                      left: 12,
                      bottom: 10,
                      child: Semantics(
                        label: ruEn('Вы оба', 'You both'),
                        child: Text(
                          item.reaction,
                          style: const TextStyle(fontSize: 34),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Text(
              [
                ruEn('Вам обоим понравилось', 'You both reacted'),
                link.platform,
                if (when.isNotEmpty) when,
              ].join(' · '),
              style: text.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _open(item),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(ruEn('Смотреть', 'Watch')),
                ),
                OutlinedButton.icon(
                  onPressed: _saving.contains(item.id)
                      ? null
                      : () => _keep(item),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: Text(ruEn('В воспоминания', 'To memories')),
                ),
                IconButton(
                  tooltip: ruEn('Удалить совпадение', 'Delete match'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _deleting.contains(item.id)
                      ? null
                      : () => _delete(item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  final _saving = <String>{};

  Future<void> _keep(ForkReelMatch match) async {
    setState(() => _saving.add(match.id));
    try {
      final ok = await (widget.keep ?? ReelSave.save)(
        groupId: widget.groupId,
        key: match.link!.key,
      );
      if (!mounted) return;
      if (ok) {
        ForkNotice.info(
          context,
          ruEn('Ролик в воспоминаниях', 'Saved to memories'),
        );
      } else {
        ForkNotice.failure(
          context,
          ForkFailure.unknown,
          retry: () => _keep(match),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(match.id));
    }
  }
}
