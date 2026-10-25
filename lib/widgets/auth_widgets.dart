import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme_scope.dart';
import '../theme/profile_theme.dart';

/// Общие виджеты экранов входа/регистрации (единый стиль «карточка + поля с
/// плавающей подписью + ряд соц-иконок»). [accent] берётся из вызывающего
/// экрана (вход — розовый, регистрация — по полу), чтобы рамка/подпись поля
/// и кнопки красились темой.

/// Поле с плавающей подписью: подпись всегда на верхней границе, плейсхолдер
/// внутри. Для пароля — встроенный тоггл видимости.
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final Color accent;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool isPassword;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.accent,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.isPassword = false,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final cs = ProfileTheme.themeFor(t).colorScheme;
    // M3: поле-таблетка, filled тональным, без рамки (только тонкий фокус-ринг).
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      obscureText: widget.isPassword && _obscure,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      cursorColor: cs.primary,
      style: TextStyle(
        fontFamily: 'Onest',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        fontVariations: const [FontVariation('wght', 500)],
        color: cs.onSurface,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(
          fontFamily: 'Onest',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
          color: cs.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: 'Onest',
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation('wght', 700)],
          color: cs.primary,
        ),
        hintText: widget.hint,
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 18,
        ),
        suffixIcon: widget.isPassword
            ? GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: cs.onSurfaceVariant,
                  size: 20,
                ),
              )
            : null,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
      ),
    );
  }
}
