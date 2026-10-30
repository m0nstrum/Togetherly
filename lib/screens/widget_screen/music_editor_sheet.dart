import 'dart:async';
import '../../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../services/locale_service.dart';
import '../../services/music_meta_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_sheet.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MUSIC EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

/// Supported music services for the info dialog
const List<Map<String, dynamic>> musicServicesList = [
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
    'name': 'Yandex Music',
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
    'name': 'VK Music',
    'supported': true,
    'color': Color(0xFF0077FF),
    'icon': Icons.music_video_rounded,
  },
  {
    'name': 'YouTube',
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

class MusicEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String initialTitle;
  final String initialArtist;
  final String initialUrl;
  final String initialCoverUrl;
  final void Function({
    required String title,
    required String artist,
    String? url,
    String? coverUrl,
  })
  onSave;

  const MusicEditorSheet({
    super.key,
    required this.theme,
    required this.initialTitle,
    required this.initialArtist,
    required this.initialUrl,
    required this.initialCoverUrl,
    required this.onSave,
  });

  @override
  State<MusicEditorSheet> createState() => _MusicEditorSheetState();
}

class _MusicEditorSheetState extends State<MusicEditorSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;
  late TextEditingController _urlCtrl;
  late FocusNode _urlFocus;

  bool _isFetching = false;
  String? _coverUrl;
  Timer? _debounce;
  String? _lastFetchedUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _artistCtrl = TextEditingController(text: widget.initialArtist);
    _urlCtrl = TextEditingController(text: widget.initialUrl);
    _coverUrl = widget.initialCoverUrl.isNotEmpty
        ? widget.initialCoverUrl
        : null;

    _urlFocus = FocusNode();
    _urlFocus.addListener(() {
      if (!_urlFocus.hasFocus) _triggerFetch();
    });
  }

  /// Сохранение с догрузкой. Прежняя кнопка на пустых полях просто выходила
  /// молча (`if (title.isEmpty || artist.isEmpty) return`), и человек с
  /// вставленной ссылкой упирался в мёртвую кнопку без единого слова.
  Future<void> _saveMusic() async {
    final url = _urlCtrl.text.trim();
    final needMeta =
        _titleCtrl.text.trim().isEmpty || _artistCtrl.text.trim().isEmpty;
    if (needMeta && url.isNotEmpty && url != _lastFetchedUrl) {
      await _triggerFetch();
    }
    if (!mounted) return;

    final title = _titleCtrl.text.trim();
    final artist = _artistCtrl.text.trim();
    if (title.isEmpty || artist.isEmpty) {
      // Снекбар отсюда не виден: лист лежит маршрутом поверх Scaffold, и
      // сообщение уезжает под него (те же грабли, что у «Ждём человека»).
      setState(() => _error = LocaleService.current.musicMetaNotFound);
      return;
    }
    widget.onSave(
      title: title,
      artist: artist,
      url: url.isNotEmpty ? url : null,
      coverUrl: _coverUrl,
    );
  }

  /// Подгрузка по вставке ссылки, а не по уходу курсора из поля. Раньше
  /// сработать успевал только тот, кто нажимал куда-то ещё перед сохранением;
  /// остальные вписывали автора и название руками, хотя приложение умеет их
  /// доставать само.
  void _onUrlChanged(String value) {
    final url = value.trim();
    if (_error != null) setState(() => _error = null);
    _debounce?.cancel();
    if (!url.startsWith('http') || !url.contains('.')) return;
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (url != _lastFetchedUrl) _triggerFetch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _triggerFetch() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) return;
    if (!mounted || _isFetching) return;
    _lastFetchedUrl = url;
    setState(() => _isFetching = true);
    final meta = await _fetchMusicMeta(url);
    if (!mounted) return;
    setState(() {
      _isFetching = false;
      if ((meta['title']?.isNotEmpty ?? false) && _titleCtrl.text.isEmpty) {
        _titleCtrl.text = meta['title']!;
      }
      if ((meta['artist']?.isNotEmpty ?? false) && _artistCtrl.text.isEmpty) {
        _artistCtrl.text = meta['artist']!;
      }
      if (meta['cover']?.isNotEmpty ?? false) {
        _coverUrl = meta['cover'];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.theme.primary;
    // Ссылка, обложка и два поля выше маленького экрана, особенно с открытой
    // клавиатурой: лист листается, а не обрезает «Сохранить».
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: widget.theme.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.theme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // ── Header with info button ──
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleService.current.music,
                    style: AppFonts.onest(
                      size: 18,
                      weight: 800,
                      color: widget.theme.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showServicesInfo(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── Link Section (first — paste link to auto-fill below) ───
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.theme.surfaceMuted,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.theme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        LocaleService.current.streamingLink,
                        style: AppFonts.onest(
                          size: 14,
                          weight: 700,
                          color: widget.theme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // URL field with fetch button
                  TextField(
                    controller: _urlCtrl,
                    focusNode: _urlFocus,
                    keyboardType: TextInputType.url,
                    style: AppFonts.onest(size: 15),
                    onChanged: _onUrlChanged,
                    onSubmitted: (_) => _triggerFetch(),
                    decoration: InputDecoration(
                      hintText: LocaleService.current.pasteLinkFromService,
                      hintStyle: TextStyle(
                        fontFamily: AppFonts.body,
                        color: widget.theme.textMuted,
                      ),
                      prefixIcon: Icon(
                        Icons.link_rounded,
                        color: primary,
                        size: 20,
                      ),
                      suffixIcon: _isFetching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                Icons.manage_search_rounded,
                                color: primary,
                              ),
                              tooltip: LocaleService.current.autoFetchSongInfo,
                              onPressed: _triggerFetch,
                            ),
                      filled: true,
                      fillColor: widget.theme.cardSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ─── Song Details Section ───
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withOpacity(0.04),
                    const Color(0xFFEC4899).withOpacity(0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: primary.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Album cover preview
                      if (_coverUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: StorageImage(
                              imageUrl: _coverUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.music_note_rounded,
                                  size: 22,
                                  color: primary,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              size: 16,
                              color: primary,
                            ),
                          ),
                        ),
                      Text(
                        LocaleService.current.songDetails,
                        style: AppFonts.onest(
                          size: 14,
                          weight: 700,
                          color: widget.theme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    _titleCtrl,
                    LocaleService.current.trackName,
                    Icons.audiotrack_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    _artistCtrl,
                    LocaleService.current.artist,
                    Icons.person_rounded,
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: AppFonts.onest(
                    size: 13.5,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isFetching ? null : _saveMusic,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  LocaleService.current.save,
                  style: AppFonts.onest(size: 15, weight: 700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Music metadata fetching (same logic as Memory Lane) ──

  /// Метаданные трека по ссылке. Разбор живёт в [MusicMetaService] — одной
  /// копией на оба экрана: пока копий было две, они разошлись, и в виджете
  /// Яндекс.Музыка подставляла в поля мусор вместо названия.
  Future<Map<String, String?>> _fetchMusicMeta(String url) =>
      MusicMetaService.instance.fetch(url);

  void _showServicesInfo(BuildContext context) {
    final primary = widget.theme.primary;
    showAppSheet<void>(
      context,
      builder: (ctx) => SheetScaffold(
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
                'Supported Services',
                style: AppFonts.onest(
                  size: 18,
                  weight: 800,
                  color: widget.theme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Paste a link from any supported service',
                style: AppFonts.onest(size: 12, color: widget.theme.textMuted),
              ),
              const SizedBox(height: 18),
              ...musicServicesList.map(
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
                            style: AppFonts.onest(
                              size: 14,
                              weight: 600,
                              color: widget.theme.textPrimary,
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
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Got it',
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: AppFonts.onest(size: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: widget.theme.textMuted,
        ),
        prefixIcon: Icon(icon, color: widget.theme.primary, size: 20),
        filled: true,
        fillColor: widget.theme.surfaceMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: widget.theme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
