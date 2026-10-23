import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/locale_service.dart';
import '../../widgets/app_sheet.dart';

/// Choosing/confirming the recipient is separate from sending the request.
Future<String?> forkPasswordResetEmail(
  BuildContext context, {
  String initial = '',
}) => showAppSheet<String>(
  context,
  builder: (_) => _ResetEmail(initial: initial),
);

class _ResetEmail extends StatefulWidget {
  const _ResetEmail({required this.initial});
  final String initial;
  @override
  State<_ResetEmail> createState() => _ResetEmailState();
}

class _ResetEmailState extends State<_ResetEmail> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _email.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
    title: LocaleService.current.forgotPassword,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ruEn(
                'Отправим письмо со ссылкой для смены пароля на этот адрес.',
                'We’ll send a password reset link to this email address.',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: LocaleService.current.email,
              ),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : LocaleService.current.invalidEmail,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: Text(ruEn('Отправить письмо', 'Send email')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(LocaleService.current.cancel),
            ),
          ],
        ),
      ),
    ),
  );
}
