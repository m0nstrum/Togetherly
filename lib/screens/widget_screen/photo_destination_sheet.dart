import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PHOTO DESTINATION SHEET — куда отправить фото из парного виджета
// ══════════════════════════════════════════════════════════════════════════════

/// Результат выбора направлений для загруженного фото.
class PhotoDestinations {
  final bool toPairWidget;
  final bool toPartnerWidget;
  final bool toMemories;
  const PhotoDestinations({
    required this.toPairWidget,
    required this.toPartnerWidget,
    required this.toMemories,
  });
}

class PhotoDestinationSheet extends StatefulWidget {
  final AppTheme theme;
  final String partnerName;
  final bool initialToPairWidget;
  final bool initialToPartnerWidget;
  final bool initialToMemories;

  const PhotoDestinationSheet({
    super.key,
    required this.theme,
    required this.partnerName,
    required this.initialToPairWidget,
    required this.initialToPartnerWidget,
    required this.initialToMemories,
  });

  @override
  State<PhotoDestinationSheet> createState() => _PhotoDestinationSheetState();
}

class _PhotoDestinationSheetState extends State<PhotoDestinationSheet> {
  late bool _toPairWidget = widget.initialToPairWidget;
  late bool _toPartnerWidget = widget.initialToPartnerWidget;
  late bool _toMemories = widget.initialToMemories;

  AppTheme get _t => widget.theme;

  @override
  Widget build(BuildContext context) {
    final partner = widget.partnerName.isNotEmpty
        ? widget.partnerName
        : LocaleService.current.partnerFallback;
    final nothingSelected = !_toPairWidget && !_toPartnerWidget && !_toMemories;

    return Container(
      decoration: BoxDecoration(
        color: _t.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _t.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            LocaleService.current.whereToSendPhoto,
            style: AppFonts.onest(size: 18, weight: 800, color: _t.textPrimary),
          ),
          const SizedBox(height: 16),
          _destTile(
            icon: Icons.dashboard_customize_rounded,
            title: LocaleService.current.captionDestPairWidget,
            subtitle: LocaleService.current.captionDestPairWidgetSub(partner),
            value: _toPairWidget,
            onChanged: (v) => setState(() => _toPairWidget = v),
          ),
          _destTile(
            icon: Icons.favorite_rounded,
            title: LocaleService.current.captionDestPartnerWidget,
            subtitle: LocaleService.current.captionDestPartnerWidgetSub(
              partner,
            ),
            value: _toPartnerWidget,
            onChanged: (v) => setState(() => _toPartnerWidget = v),
          ),
          _destTile(
            icon: Icons.photo_album_rounded,
            title: LocaleService.current.captionDestMemories,
            subtitle: LocaleService.current.captionDestMemoriesSub,
            value: _toMemories,
            onChanged: (v) => setState(() => _toMemories = v),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: nothingSelected
                  ? null
                  : () => Navigator.pop(
                      context,
                      PhotoDestinations(
                        toPairWidget: _toPairWidget,
                        toPartnerWidget: _toPartnerWidget,
                        toMemories: _toMemories,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _t.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _t.surfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                LocaleService.current.sendLabel,
                style: AppFonts.onest(size: 15, weight: 700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _destTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: _t.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.onest(
                    size: 14,
                    weight: 700,
                    color: _t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppFonts.onest(
                    size: 11.5,
                    height: 1.25,
                    color: _t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            activeColor: _t.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
