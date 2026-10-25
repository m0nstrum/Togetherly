import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/pb_data_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../profile/profile_hero.dart';
import '../../fork/profile/partner_page.dart'; // fork: страница партнёра
import '../../widgets/widget_content_view.dart'
    show openWidgetPhotoView; // fork

/// Профиль партнёра в том же виде, что и наш: общая шапка [ProfileHero]
/// (серверный баннер + аватар + имя/дни), только показ. Ниже — «Открытка»
/// [GiftProfileBody]: полка подарков и столбики по дням недели «Я скучаю».
class PartnerProfileScreen extends StatefulWidget {
  const PartnerProfileScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.partnerUid,
    required this.partnerName,
    this.partnerAvatarUrl,
    this.daysTogether,
  });

  final AppTheme theme;
  final String groupId;
  final String partnerUid;
  final String partnerName;
  final String? partnerAvatarUrl;
  final int? daysTogether;

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  // Ключ живёт в поле, а не в build(): иначе pull-to-refresh пересоздавал бы
  // состояние тела на каждой перестройке и сбрасывал загруженные данные.
  final _bodyKey = GlobalKey<ForkPartnerPageState>(); // fork
  String _bannerUrl = '';

  /// fork: карточка партнёра — дата рождения и пол для страницы ниже.
  Map<String, dynamic>? _card;

  /// Шевелится ли GIF партнёра: у него открыт Togetherly+. Чужой флаг `plus`
  /// клиенту не виден, его считает сервер в карточке (`banner_live`).
  bool _bannerLive = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    final m = await PbDataService().loadPartnerCard(widget.partnerUid);
    if (!mounted || m == null) return;
    setState(() => _card = m); // fork
    final b = (m['bannerUrl'] as String?) ?? '';
    final live = m['bannerLive'] == true;
    if (b != _bannerUrl || live != _bannerLive) {
      setState(() {
        _bannerUrl = b;
        _bannerLive = live;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final cs = ProfileTheme.themeFor(t).colorScheme;
    final days = widget.daysTogether;
    final subtitle = days != null
        ? LocaleService.current.partnerDaysTogether(days)
        : '';
    return Scaffold(
      backgroundColor: cs.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadBanner();
          await (_bodyKey.currentState?.reload() ?? Future.value());
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            ProfileHero(
              cs: cs,
              uid: widget.partnerUid,
              avatarUrl: widget.partnerAvatarUrl ?? '',
              name: widget.partnerName,
              bannerUrl: _bannerUrl,
              bannerAnimated: _bannerLive,
              subtitle: subtitle,
              // fork: фото партнёра целиком — касанием по аватару.
              onTapAvatar: (widget.partnerAvatarUrl ?? '').isEmpty
                  ? null
                  : () => openWidgetPhotoView(
                      context,
                      imageUrl: widget.partnerAvatarUrl!,
                      authorName: widget.partnerName,
                    ),
            ),
            const SizedBox(height: 52),
            // fork: вместо одной полки подарков — что известно о партнёре.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ForkPartnerPage(
                key: _bodyKey,
                theme: t,
                groupId: widget.groupId,
                partnerUid: widget.partnerUid,
                partnerName: widget.partnerName,
                partnerAvatarUrl: widget.partnerAvatarUrl,
                daysTogether: widget.daysTogether,
                card: _card,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
