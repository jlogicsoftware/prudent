import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'erase_account_form.dart';
import 'privacy_actions.dart';

/// What Prudent keeps, and the two things a person can do about it: take a copy of all of it, and
/// delete all of it (M0, jlogicsoftware/prudent#48, ADR-071). The full policy is
/// `docs/privacy-policy.md`; the three paragraphs here are what a person needs before pressing
/// either button.
///
/// The copy goes to the clipboard as readable JSON. A file save would need a platform package for
/// each target that the app does not otherwise carry, and the clipboard works the same on all six;
/// saving to a file is a follow-up, not a reason to ship no export.
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;

  Future<void> _export(PrudentLocalizations t) async {
    setState(() => _exporting = true);
    String message;
    try {
      final json = await ref.read(privacyActionsProvider).exportJson();
      await Clipboard.setData(ClipboardData(text: json));
      message = t.privacyExportDone;
    } on ZenError catch (error) {
      message = error.message.isEmpty ? t.privacyExportFailed : error.message;
    }
    if (!mounted) return;
    setState(() => _exporting = false);
    showZenMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final theme = Theme.of(context);

    return ZenPageScaffold(
      title: t.privacyTitle,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.privacyPolicyStored, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(t.privacyPolicyRights, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Text(t.privacyPolicyLimits, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          Text(t.privacyExportHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ZenButton(
              label: t.privacyExportAction,
              variant: ZenButtonVariant.secondary,
              isLoading: _exporting,
              onPressed: () => _export(t),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: ZenButton(
              label: t.privacyEraseAction,
              variant: ZenButtonVariant.secondary,
              onPressed:
                  () => showAdaptivePresentation<void>(
                    context,
                    builder: (_) => const EraseAccountForm(),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
