import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/wish.dart';
import '../../models/wish_comment.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';

/// Комментарии к желанию (docs/WISHLIST.md): договориться о дне, уточнить
/// размер. Пишут оба, удаляет своё только автор.
Future<void> showWishCommentsSheet(
  BuildContext context, {
  required AppTheme theme,
  required Wish wish,
  required String myUid,
  required Stream<List<WishComment>> comments,
  required String Function(String uid) nameOf,
  required Future<void> Function(String text) onSend,
  required Future<void> Function(WishComment c) onDelete,
}) {
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: WishCommentsSheet(
        wish: wish,
        myUid: myUid,
        comments: comments,
        nameOf: nameOf,
        onSend: onSend,
        onDelete: onDelete,
      ),
    ),
  );
}

class WishCommentsSheet extends StatefulWidget {
  const WishCommentsSheet({
    super.key,
    required this.wish,
    required this.myUid,
    required this.comments,
    required this.nameOf,
    required this.onSend,
    required this.onDelete,
  });

  final Wish wish;
  final String myUid;

  /// Все комментарии пары: лист берёт свои по id желания.
  final Stream<List<WishComment>> comments;
  final String Function(String uid) nameOf;
  final Future<void> Function(String text) onSend;
  final Future<void> Function(WishComment c) onDelete;

  @override
  State<WishCommentsSheet> createState() => _WishCommentsSheetState();
}

class _WishCommentsSheetState extends State<WishCommentsSheet> {
  final TextEditingController _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      _text.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDelete(WishComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ruEn('Удалить комментарий?', 'Delete the comment?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ruEn('Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ruEn('Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) await widget.onDelete(c);
  }

  String _when(DateTime at) {
    final s = LocaleService.current;
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '${s.dayLogDate(at)}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetScaffold(
      title: widget.wish.title,
      bottom: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('wish-comment-field'),
              controller: _text,
              maxLength: 500,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                hintText: ruEn('Написать…', 'Write…'),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('wish-comment-send'),
            tooltip: ruEn('Отправить', 'Send'),
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
      child: StreamBuilder<List<WishComment>>(
        stream: widget.comments,
        builder: (context, snap) {
          final list = (snap.data ?? const <WishComment>[])
              .where((c) => c.wishId == widget.wish.id)
              .toList();
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                ruEn(
                  'Пока без комментариев. Договоритесь о дне или '
                      'уточните детали.',
                  'No comments yet. Agree on a day or add details.',
                ),
                style: AppFonts.onest(
                  size: 14,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final c = list[i];
              final mine = c.authorUid == widget.myUid;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  key: Key('wish-comment-${c.id}'),
                  onLongPress: mine ? () => _confirmDelete(c) : null,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: mine
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            if (!mine) widget.nameOf(c.authorUid),
                            _when(c.createdAt),
                          ].where((t) => t.isNotEmpty).join(' · '),
                          style: AppFonts.onest(
                            size: 11.5,
                            weight: 600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.text,
                          style: AppFonts.onest(
                            size: 15,
                            height: 1.4,
                            color: mine ? cs.onPrimaryContainer : cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
