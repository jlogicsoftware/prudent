import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../l10n/generated/prudent_localizations.dart';
import 'erase_account_form.dart';
import 'export_file_saver.dart';
import 'privacy_actions.dart';

/// What Prudent keeps, and the two things a person can do about it: take a copy of all of it, and
/// delete all of it (M0, jlogicsoftware/prudent#48, ADR-071). The full policy is
/// `docs/privacy-policy.md`; the three paragraphs here are what a person needs before pressing
/// either button.
///
/// The copy goes to the clipboard as readable JSON, or, where the platform can, to a file the person
/// chooses (unit 10a, ADR-110). The file is the way to carry the data to Prudent Local (ADR-103); it
/// is not encrypted and the screen says so before the button, not after it. On iOS and Android there
/// is no file save yet, so only the clipboard copy is offered there.
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
    } finally {
      // Whatever was thrown, the button stops spinning; an Error that is not handled above still
      // propagates after this.
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    showZenMessage(context, message);
  }

  Future<void> _save(PrudentLocalizations t) async {
    setState(() => _exporting = true);
    String? message;
    try {
      final file = await ref.read(privacyActionsProvider).exportFile();
      final saved = await ref.read(exportFileSaverProvider)(file.name, file.bytes);
      // A browser download is not a save the person chose the place of, so it is worded as one.
      final byDownload = ref.read(exportFileSavedByDownloadProvider);
      message = !saved
          ? null
          : (byDownload ? t.privacyExportDownloadDone : t.privacyExportSaveDone);
    } on ZenError catch (error) {
      message = error.message.isEmpty ? t.privacyExportFailed : error.message;
    } on Exception catch (error, stack) {
      // The platform refused the write. Say so; the details go to the log, not the screen.
      developer.log('saving the export failed', error: error, stackTrace: stack);
      message = t.privacyExportSaveFailed;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (!mounted) return;
    if (message != null) showZenMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final canSave = ref.watch(exportFileSavingSupportedProvider);
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
          if (canSave) ...[
            Text(t.privacyExportSaveWarning, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ZenButton(
                label: t.privacyExportSaveAction,
                variant: ZenButtonVariant.secondary,
                isLoading: _exporting,
                onPressed: () => _save(t),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(t.privacyExportHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(t.privacyExportCopyWarning, style: theme.textTheme.bodySmall),
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
