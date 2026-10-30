import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/screens/memory_lane/video_link_meta.dart';

/// A12-2: метаданные видео по ссылке — вынесены с экрана воспоминаний.
void main() {
  http.Response ok(String body) => http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response oembed(String title) => ok(
    jsonEncode({
      'title': title,
      'author_name': 'Канал',
      'thumbnail_url': 'https://img/$title.jpg',
    }),
  );

  group('площадка по адресу', () {
    test('известные площадки и иконки', () {
      final yt = VideoLinkMeta.detectPlatform('https://youtu.be/abc');
      expect(yt['name'], 'YouTube');
      expect(yt['color'], const Color(0xFFFF0000));
      expect(
        VideoLinkMeta.detectPlatform('https://VKVIDEO.ru/x')['name'],
        'VK Video',
      );
      expect(
        VideoLinkMeta.platformIcon('YouTube'),
        Icons.smart_display_rounded,
      );
      expect(VideoLinkMeta.platformIcon('Нечто'), Icons.videocam_rounded);
    });
  });

  test('YouTube — официальный oEmbed', () async {
    final asked = <Uri>[];
    final meta = VideoLinkMeta(
      client: MockClient((req) async {
        asked.add(req.url);
        return oembed('Клип');
      }),
    );
    final got = await meta.fetch('https://youtu.be/abc');
    expect(got, {
      'title': 'Клип',
      'author': 'Канал',
      'cover': 'https://img/Клип.jpg',
    });
    expect(asked.single.host, 'www.youtube.com');
    expect(asked.single.queryParameters['url'], 'https://youtu.be/abc');
  });

  test('YouTube без ответа — пусто, запасные пути не трогаем', () async {
    var calls = 0;
    final meta = VideoLinkMeta(
      client: MockClient((_) async {
        calls++;
        return http.Response('', 404);
      }),
    );
    expect(await meta.fetch('https://youtube.com/watch?v=1'), isEmpty);
    expect(calls, 1);
  });

  test('Vimeo не ответил — noembed', () async {
    final hosts = <String>[];
    final meta = VideoLinkMeta(
      client: MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'vimeo.com') return http.Response('', 500);
        return oembed('Из noembed');
      }),
    );
    final got = await meta.fetch('https://vimeo.com/1');
    expect(got['title'], 'Из noembed');
    expect(hosts, ['vimeo.com', 'noembed.com']);
  });

  test('noembed с ошибкой — OG-теги страницы, сущности раскрыты', () async {
    final meta = VideoLinkMeta(
      client: MockClient((req) async {
        if (req.url.host == 'noembed.com') {
          return ok(jsonEncode({'error': 'no'}));
        }
        expect(req.headers['User-Agent'], contains('Twitterbot'));
        return ok(
          '<meta property="og:title" content="Tom &amp; Jerry &#39;24">'
          '<meta property="og:image" content="https://img/og.jpg">'
          '<meta name="author" content="Автор">',
        );
      }),
    );
    final got = await meta.fetch('https://rutube.ru/video/1');
    expect(got, {
      'title': "Tom & Jerry '24",
      'author': 'Автор',
      'cover': 'https://img/og.jpg',
    });
  });

  test('сеть упала везде — пусто, без исключения', () async {
    final meta = VideoLinkMeta(
      client: MockClient((_) async => throw http.ClientException('нет сети')),
    );
    expect(await meta.fetch('https://dailymotion.com/v/1'), isEmpty);
  });
}
