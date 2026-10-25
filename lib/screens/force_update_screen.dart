import 'package:flutter/material.dart';
import '../utils/safe_launch.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/locale_service.dart';
import '../theme/theme_scope.dart';
import '../fork/config/endpoints.dart'; // fork

/// Блокирующий экран принудительного обновления.
///
/// Показывается на старте, когда установленная сборка ниже минимально
/// поддерживаемой (`app_config.min_build` в Supabase). Выйти нельзя —
/// единственное действие ведёт на страницу релиза.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  /// Страница последнего релиза; сборка сама из магазина не обновляется.
  static final String _releasesLatestUrl = Endpoints.current.releasesUrl; // fork

  Future<void> _openUpdate() async {
    if (_releasesLatestUrl.isNotEmpty) await _launch(_releasesLatestUrl);
  }

  Future<bool> _launch(String url) async {
    try {
      return await safeLaunchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final accent = Theme.of(context).colorScheme.primary;
    final t = context.appTheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: accent,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    s.forceUpdateTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.forceUpdateBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _openUpdate,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        s.forceUpdateButton,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
