import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'privacy_actions.dart';

/// The last step before everything is deleted: it says what will go and asks the person to type the
/// address they sign in with (M0, jlogicsoftware/prudent#48, ADR-071).
///
/// The address is checked by the server, not here: it is the one that knows it, and a refusal comes
/// back in its words with the form left open and nothing deleted. On success the session ends and
/// the app returns to sign-in on its own, so the form does not close itself.
class EraseAccountForm extends ConsumerStatefulWidget {
  const EraseAccountForm({super.key});

  @override
  ConsumerState<EraseAccountForm> createState() => _EraseAccountFormState();
}

class _EraseAccountFormState extends ConsumerState<EraseAccountForm> {
  final _email = TextEditingController();
  String? _failure;
  bool _erasing = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit(PrudentLocalizations t) async {
    setState(() {
      _erasing = true;
      _failure = null;
    });
    try {
      await ref.read(privacyActionsProvider).erase(_email.text.trim());
    } on ZenError catch (error) {
      if (!mounted) return;
      setState(() {
        _erasing = false;
        _failure = error.message.isEmpty ? t.privacyEraseFailed : error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.privacyEraseTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t.privacyEraseBody, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          ZenTextField(
            label: t.privacyEraseEmailField,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onChanged: (_) => setState(() {}),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 8),
            Text(_failure!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ZenButton(
                label: t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: _erasing ? null : () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              ZenButton(
                label: t.privacyEraseConfirm,
                isLoading: _erasing,
                onPressed: _email.text.trim().isEmpty ? null : () => _submit(t),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
