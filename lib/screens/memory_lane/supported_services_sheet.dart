import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';

// Листы «какие сервисы поддерживаются» из форм музыки и видео по ссылке
// (A12-2): перенесены с экрана без правок, тема — параметром.

/// Supported music services list for the info dialog
const List<Map<String, dynamic>> _supportedMusicServices = [
  {
    'name': 'Spotify',
    'supported': true,
    'color': Color(0xFF1DB954),
    'icon': Icons.music_note_rounded,
  },
  {
    'name': 'YouTube Music',
    'supported': true,
    'color': Color(0xFFFF0000),
    'icon': Icons.play_circle_rounded,
  },
  {
    'name': 'Apple Music',
    'supported': true,
    'color': Color(0xFFFC3C44),
    'icon': Icons.apple_rounded,
  },
  {
    'name': 'Deezer',
    'supported': true,
    'color': Color(0xFFA238FF),
    'icon': Icons.album_rounded,
  },
  {
    'name': 'SoundCloud',
    'supported': true,
    'color': Color(0xFFFF5500),
    'icon': Icons.cloud_rounded,
  },
  {
    'name': 'Яндекс Музыка',
    'supported': true,
    'color': Color(0xFFFFCC00),
    'icon': Icons.library_music_rounded,
  },
  {
    'name': 'Tidal',
    'supported': true,
    'color': Color(0xFF000000),
    'icon': Icons.waves_rounded,
  },
  {
    'name': 'YouTube Music',

    'supported': true,
    'color': Color(0xFFFF0000),
    'icon': Icons.smart_display_rounded,
  },
  {
    'name': 'Audio file',
    'supported': true,
    'color': Color(0xFF8B5CF6),
    'icon': Icons.audio_file_rounded,
  },
  {
    'name': 'Amazon Music',
    'supported': false,
    'color': Color(0xFF25D1DA),
    'icon': Icons.shopping_bag_rounded,
  },
  {
    'name': 'Pandora',
    'supported': false,
    'color': Color(0xFF005483),
    'icon': Icons.radio_rounded,
  },
];

const List<Map<String, dynamic>> _supportedVideoServices = [
  {
    'name': 'YouTube',
    'supported': true,
    'color': Color(0xFFFF0000),
    'icon': Icons.smart_display_rounded,
  },
  {
    'name': 'Vimeo',
    'supported': true,
    'color': Color(0xFF1AB7EA),
    'icon': Icons.play_circle_rounded,
  },
  {
    'name': 'Dailymotion',
    'supported': true,
    'color': Color(0xFF0066DC),
    'icon': Icons.play_circle_outline_rounded,
  },
  {
    'name': 'Twitch',
    'supported': true,
    'color': Color(0xFF9146FF),
    'icon': Icons.live_tv_rounded,
  },
  {
    'name': 'TikTok',
    'supported': true,
    'color': Color(0xFF010101),
    'icon': Icons.music_video_rounded,
  },
  {
    'name': 'Instagram',
    'supported': true,
    'color': Color(0xFFE1306C),
    'icon': Icons.camera_alt_rounded,
  },
  {
    'name': 'Facebook',
    'supported': true,
    'color': Color(0xFF1877F2),
    'icon': Icons.facebook_rounded,
  },
  {
    'name': 'Twitter / X',
    'supported': true,
    'color': Color(0xFF000000),
    'icon': Icons.alternate_email_rounded,
  },
  {
    'name': 'Rutube',
    'supported': true,
    'color': Color(0xFF1482C8),
    'icon': Icons.play_circle_outline_rounded,
  },
  {
    'name': 'VK Video',
    'supported': true,
    'color': Color(0xFF0077FF),
    'icon': Icons.play_circle_outline_rounded,
  },
];

/// Видеоплощадки, ссылки с которых понимает форма.
class SupportedVideoServicesSheet extends StatelessWidget {
  const SupportedVideoServicesSheet({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primary;
    return SheetScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primary.withOpacity(0.15),
                    const Color(0xFFFF0000).withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_display_rounded,
                color: primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              LocaleService.current.supportedPlatforms,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: theme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              LocaleService.current.pasteLinkSupported,
              style: TextStyle(fontSize: 12, color: theme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  children: _supportedVideoServices.map((svc) {
                    final svcColor = svc['color'] as Color;
                    final row = Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: svcColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: svcColor.withOpacity(0.12)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              svc['icon'] as IconData,
                              size: 20,
                              color: svcColor,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                svc['name'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textPrimary,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: const Color(0xFF22C55E),
                            ),
                          ],
                        ),
                      ),
                    );
                    return row;
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  LocaleService.current.gotIt,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Музыкальные сервисы: какие поддерживаются, какие нет.
class SupportedMusicServicesSheet extends StatelessWidget {
  const SupportedMusicServicesSheet({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primary;
    return SheetScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primary.withOpacity(0.15),
                    const Color(0xFFEC4899).withOpacity(0.1),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.music_note_rounded, color: primary, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              LocaleService.current.supportedServices,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleService.current.pasteLinkFromService,
              style: TextStyle(fontSize: 12, color: theme.textMuted),
            ),
            const SizedBox(height: 18),
            ..._supportedMusicServices.map(
              (svc) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: (svc['color'] as Color).withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (svc['color'] as Color).withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        svc['icon'] as IconData,
                        size: 20,
                        color: svc['color'] as Color,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          svc['name'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        svc['supported'] == true
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 20,
                        color: svc['supported'] == true
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  LocaleService.current.gotIt,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
