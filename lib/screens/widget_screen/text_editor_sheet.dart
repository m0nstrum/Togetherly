import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TEXT EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

class WidgetTextEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String title;
  final String hint;
  final String initial;
  final int maxLength;
  final ValueChanged<String> onSave;

  const WidgetTextEditorSheet({
    super.key,
    required this.theme,
    required this.title,
    required this.hint,
    required this.initial,
    required this.maxLength,
    required this.onSave,
  });

  @override
  State<WidgetTextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<WidgetTextEditorSheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            Text(
              widget.title,
              style: AppFonts.onest(
                size: 18,
                weight: 800,
                color: widget.theme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: widget.maxLength,
              maxLines: widget.maxLength > 100 ? 3 : 1,
              style: AppFonts.onest(size: 16),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: AppFonts.body,
                  color: widget.theme.textMuted,
                ),
                filled: true,
                fillColor: widget.theme.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: widget.theme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => widget.onSave(_ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primary,
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
}
