import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/reels/tiktok_comments.dart';

/// Комментарии TikTok: ответ площадки → лист в ленте (22.10).
void main() {
  // Форма ответа `/api/comment/list/` (проверено на tiktok.com 22.10.2026),
  // значения выдуманы.
  final sample = jsonEncode({
    'status_code': 0,
    'total': 39758,
    'cursor': 20,
    'has_more': 1,
    'comments': [
      {
        'cid': '7697856144556000008',
        'text': 'Это лучшее за сегодня',
        'digg_count': 595860,
        'reply_comment_total': 1100,
        'create_time': 1791483150,
        'is_author_digged': true,
        'author_pin': false,
        'stick_position': 1,
        'image_list': null,
        'user': {
          'nickname': 'Зритель',
          'unique_id': 'viewer',
          'avatar_thumb': {
            'url_list': ['https://p19.tiktokcdn.com/a.jpg']
          },
          'uid': '123',
          'sec_uid': 'secret',
        },
      },
      {'cid': '', 'text': 'без номера — мимо'},
      {
        'cid': '7697856144556000009',
        'text': '',
        'image_list': [{}],
        'user': {
          'unique_id': 'only_id',
          'avatar_thumb': {
            'url_list': ['http://insecure/a.jpg']
          },
        },
      },
    ],
  });

  test('сжатый ответ: только то, что рисует лист', () {
    final r = ForkTikTokComments.parse(sample);
    expect(r['ok'], isTrue);
    expect((r['total'], r['cursor'], r['more']), (39758, 20, true));
    final items = (r['items'] as List).cast<Map<String, dynamic>>();
    expect(items, hasLength(2), reason: 'комментарий без номера пропущен');
    expect(items.first, {
      'cid': '7697856144556000008',
      'name': 'Зритель',
      'avatar': 'https://p19.tiktokcdn.com/a.jpg',
      'text': 'Это лучшее за сегодня',
      'likes': 595860,
      'replies': 1100,
      'time': 1791483150,
      'authorLiked': true,
      'pinned': true,
      'photo': false,
    });
    expect(items.last['name'], 'only_id');
    expect(items.last['avatar'], '', reason: 'только https');
    expect(items.last['photo'], isTrue);
    expect(jsonEncode(r), isNot(contains('secret')), reason: 'лишнее о людях не уходит');
  });

  test('закрыто по стране, ошибка площадки, мусор', () {
    expect(ForkTikTokComments.parse('{"statusMsg":"ru_cross_border_block"}')['why'], 'blocked');
    expect(ForkTikTokComments.parse('{"status_code":10204}')['why'], 'blocked');
    expect(ForkTikTokComments.parse('{"status_code":5}')['why'], 'failed');
    expect(ForkTikTokComments.parse('<html>')['why'], 'failed');
    expect(ForkTikTokComments.parse('{"status_code":0}'), {'ok': true, 'total': 0, 'cursor': 0, 'more': false, 'items': []});
  });

  test('запросы: номера проверяются, пустой ответ повторяется', () async {
    final asked = <String>[];
    var empty = 1;
    final c = ForkTikTokComments(fetch: (path) async {
      asked.add(path);
      if (empty-- > 0) return '';
      return sample;
    });
    expect((await c.page(id: '../evil'))['ok'], isFalse);
    expect((await c.page(id: '7697839909842767111', cid: 'x'))['ok'], isFalse);
    expect(asked, isEmpty, reason: 'чужое в адрес не попадает');

    final r = await c.page(id: '7697839909842767111', cursor: 20);
    expect(r['ok'], isTrue);
    expect(asked, hasLength(2), reason: 'пустое тело — ещё одна попытка');
    expect(asked.last, '/api/comment/list/?aid=1988&aweme_id=7697839909842767111&count=20&cursor=20');

    await c.page(id: '7697839909842767111', cid: '7697856144556000008');
    expect(asked.last,
        '/api/comment/list/reply/?aid=1988&item_id=7697839909842767111&comment_id=7697856144556000008&count=10&cursor=0');
  });
}
