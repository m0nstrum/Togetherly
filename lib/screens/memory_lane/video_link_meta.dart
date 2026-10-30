import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/locale_service.dart';

/// Видео по ссылке: площадка по адресу и метаданные (название, канал,
/// обложка) из oEmbed или OG-тегов страницы (A12-2).
///
/// [client] — для тестов; без него каждый запрос идёт через `http.get`,
/// как раньше на экране.
class VideoLinkMeta {
  VideoLinkMeta({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<http.Response> _get(Uri url, {Map<String, String>? headers}) {
    final client = _client;
    return client == null
        ? http.get(url, headers: headers)
        : client.get(url, headers: headers);
  }

  // ── Platform detection for video URLs ──
  static Map<String, dynamic> detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return {'name': 'YouTube', 'color': const Color(0xFFFF0000)};
    } else if (lower.contains('vimeo.com')) {
      return {'name': 'Vimeo', 'color': const Color(0xFF1AB7EA)};
    } else if (lower.contains('dailymotion.com')) {
      return {'name': 'Dailymotion', 'color': const Color(0xFF0066DC)};
    } else if (lower.contains('twitch.tv')) {
      return {'name': 'Twitch', 'color': const Color(0xFF9146FF)};
    } else if (lower.contains('tiktok.com')) {
      return {'name': 'TikTok', 'color': const Color(0xFF010101)};
    } else if (lower.contains('instagram.com')) {
      return {'name': 'Instagram', 'color': const Color(0xFFE1306C)};
    } else if (lower.contains('facebook.com') || lower.contains('fb.watch')) {
      return {'name': 'Facebook', 'color': const Color(0xFF1877F2)};
    } else if (lower.contains('twitter.com') || lower.contains('x.com')) {
      return {'name': 'Twitter/X', 'color': const Color(0xFF000000)};
    } else if (lower.contains('rutube.ru')) {
      return {'name': 'Rutube', 'color': const Color(0xFF1482C8)};
    } else if (lower.contains('vk.com') || lower.contains('vkvideo.ru')) {
      return {'name': 'VK Video', 'color': const Color(0xFF0077FF)};
    } else if (lower.contains('dzen.ru')) {
      return {
        'name': LocaleService.instance.isRussian ? 'Дзен' : 'Dzen',
        'color': const Color(0xFF000000),
      };
    } else {
      return {
        'name': LocaleService.current.video,
        'color': const Color(0xFF6B7280),
      };
    }
  }

  static IconData platformIcon(String platformName) {
    switch (platformName) {
      case 'YouTube':
        return Icons.smart_display_rounded;
      case 'Twitch':
        return Icons.live_tv_rounded;
      case 'TikTok':
        return Icons.music_video_rounded;
      case 'Instagram':
        return Icons.camera_alt_rounded;
      case 'Facebook':
        return Icons.facebook_rounded;
      case 'Vimeo':
      case 'Dailymotion':
        return Icons.play_circle_rounded;
      case 'Rutube':
      case 'VK Video':
        return Icons.play_circle_outline_rounded;
      default:
        return Icons.videocam_rounded;
    }
  }

  static String decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  /// Fetch video metadata (title, channel, thumbnail) from a URL
  Future<Map<String, String?>> fetch(String url) async {
    final lower = url.toLowerCase();

    // ── YouTube (official oEmbed — no API key required) ──
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      try {
        final resp = await _get(
          Uri.parse(
            'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('YouTube video meta error: $e');
      }
      return {};
    }

    // ── Vimeo via oEmbed ──
    if (lower.contains('vimeo.com')) {
      try {
        final resp = await _get(
          Uri.parse(
            'https://vimeo.com/api/oembed.json?url=${Uri.encodeComponent(url)}',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('Vimeo meta error: $e');
      }
    }

    // ── Dailymotion via oEmbed ──
    if (lower.contains('dailymotion.com')) {
      try {
        final resp = await _get(
          Uri.parse(
            'https://www.dailymotion.com/services/oembed?url=${Uri.encodeComponent(url)}&format=json',
          ),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      } catch (e) {
        debugPrint('Dailymotion meta error: $e');
      }
    }

    // ── Generic noembed.com fallback ──
    try {
      final resp = await _get(
        Uri.parse('https://noembed.com/embed?url=${Uri.encodeComponent(url)}'),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        if (data['error'] == null) {
          return {
            'title': data['title'] as String?,
            'author': data['author_name'] as String?,
            'cover': data['thumbnail_url'] as String?,
          };
        }
      }
    } catch (_) {}

    // ── OG tags fallback ──
    try {
      final resp = await _get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (compatible; Twitterbot/1.0)'},
      );
      if (resp.statusCode == 200) {
        final body = resp.body;
        final titleMatch = RegExp(
          r'property="og:title"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        final imageMatch = RegExp(
          r'property="og:image"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        final authorMatch = RegExp(
          r'name="author"\s+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(body);
        if (titleMatch != null) {
          return {
            'title': decodeHtmlEntities(titleMatch.group(1) ?? ''),
            'author': authorMatch?.group(1),
            'cover': imageMatch?.group(1),
          };
        }
      }
    } catch (_) {}

    return {};
  }
}
