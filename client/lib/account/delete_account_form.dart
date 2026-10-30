import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/accounts.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';

/// The last step before an account and all of its transactions are deleted
/// (jlogicsoftware/prudent#201): it says what will go and asks the person to type a phrase shown
/// on the screen before the delete button works.
///
/// The phrase is a guard against a stray tap, so it is compared here; the server does not know it.
/// The delete itself is one server transaction, so a refusal or a failure comes back in the
/// server's words with the form left open and nothing deleted.
class DeleteAccountForm extends ConsumerStatefulWidget {
  const DeleteAccountForm({super.key, required this.account});

  final Account account;

  @override
  ConsumerState<DeleteAccountForm> createState() => _DeleteAccountFormState();
}

class _DeleteAccountFormState extends ConsumerState<DeleteAccountForm> {
  final _typed = TextEditingController();
  String? _failure;
  bool _deleting = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool _matches(String phrase) => _typed.text.trim().toLowerCase() == phrase.toLowerCase();

  Future<void> _submit(PrudentLocalizations t) async {
    setState(() {
      _deleting = true;
      _failure = null;
    });
    try {
      await ref
          .read(accountsProvider.notifier)
          .removeAccount(widget.account.id, deleteRecords: true);
    } on ZenError catch (error) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _failure = error.message.isEmpty ? t.accountDeleteFailed : error.message;
      });
      return;
    }
    if (!mounted) return;
    showZenMessage(context, t.accountDeleted);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);
    final phrase = t.accountDeletePhrase;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.accountDeleteFinalTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            t.accountDeleteFinalBody(widget.account.name),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            phrase,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          ZenTextField(
            label: t.accountDeletePhraseField(phrase),
            controller: _typed,
            onChanged: (_) => setState(() {}),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 8),
            Text(_failure!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          // A Wrap, not a Row: the delete label is long, longer still in Ukrainian and Polish, and on a
          // phone it must drop below Cancel rather than overflow.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              ZenButton(
                label: t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: _deleting ? null : () => Navigator.pop(context),
              ),
              ZenButton(
                label: t.accountDeleteAction,
                isLoading: _deleting,
                onPressed: _matches(phrase) ? () => _submit(t) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
