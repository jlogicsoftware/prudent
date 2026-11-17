import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prudent_local_store/prudent_local_store.dart'
    show MoveIn, MoveInRefusal, MoveInRefused, MoveInResult, MoveInRule, MovedIn;
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../app/local_providers.dart';
import '../l10n/generated/local_localizations.dart';
import '../move_in/export_file_picker.dart';
import '../move_in/move_in_messages.dart';
import '../widgets/settings_action.dart';
import '../widgets/settings_paragraph.dart';

/// Settings → Privacy and data → Move my data in (unit 10b; ADR-103, ADR-123): the server's privacy
/// export, from a file the person picks, moved into this device's empty store — whole, or not at
/// all.
///
/// - **A file, never the clipboard** (ADR-100 T14), and the page says the file is not encrypted and
///   should be deleted afterwards.
/// - **What was refused, and why, stays on the page** — a sentence in the person's language and the
///   rule's code with where in the file it was found — not a message that disappears. No free text
///   of the ledger is quoted: the facts are ids, field and currency codes, counts and amounts
///   (`MoveInRule`), and the log names the error's class only.
/// - **What was checked is said plainly**: the balances, to the cent, and nothing else; and what was
///   not moved (the profile, which reminders were read, unfinished statement imports).
/// - **The server account is not erased** by the move; the page says how to erase it once the
///   balances have been checked (ADR-103).
class MoveInScreen extends ConsumerStatefulWidget {
  const MoveInScreen({super.key});

  @override
  ConsumerState<MoveInScreen> createState() => _MoveInScreenState();
}

class _MoveInScreenState extends ConsumerState<MoveInScreen> {
  bool _busy = false;
  MoveInResult? _result;
  String? _fileProblem;

  Future<void> _choose(LocalLocalizations t) async {
    setState(() {
      _busy = true;
      _result = null;
      _fileProblem = null;
    });
    try {
      final Uint8List? bytes;
      try {
        bytes = await ref.read(exportFilePickerProvider)();
      } on ExportFileTooLarge {
        _fileProblem = t.moveInTooLarge;
        return;
      } on Exception catch (error, stack) {
        // One line of classes, never the content (ADR-100 T21).
        developer.log(
          'opening the export file failed: ${error.runtimeType}',
          name: 'prudent',
          stackTrace: stack,
        );
        _fileProblem = t.moveInFileFailed;
        return;
      }
      if (bytes == null) return; // Cancelled: nothing was asked for, so nothing is said.
      final session = ref.read(localSessionProvider);
      MoveInResult result;
      try {
        result = await MoveIn(session.prudent).run(MoveIn.read(bytes));
      } on MoveInRefusal catch (refusal) {
        result = MoveInRefused(refusal);
        // Anything else thrown by the move is a fault, not a refusal; it is still said on the page
        // rather than escaping as an unhandled error with nothing shown, and logged by class only.
      } catch (error, stack) {
        developer.log('the move failed: ${error.runtimeType}', name: 'prudent', stackTrace: stack);
        result = const MoveInRefused(MoveInRefusal(MoveInRule.storeFailed));
      }
      if (result case MoveInRefused(:final refusal)) {
        // Classes only (ADR-100 T21): the rule and its facts are on the page, not in the log.
        developer.log('the move was refused (${refusal.cause.runtimeType})', name: 'prudent');
      }
      _result = result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _outcome(LocalLocalizations t) {
    final problem = _fileProblem;
    if (problem != null) return [SettingsParagraph(problem, warning: true)];
    return switch (_result) {
      null => const [],
      MovedIn(:final summary) => [
        SettingsParagraph(
          t.moveInDone(
            summary.accounts,
            summary.records,
            summary.transfers,
            summary.plans,
            summary.budgets,
            summary.goals,
          ),
        ),
        SettingsParagraph(t.moveInChecked),
        SettingsParagraph(t.moveInNotMoved),
        if (summary.droppedImportSessions > 0)
          SettingsParagraph(t.moveInDroppedSessions(summary.droppedImportSessions)),
        SettingsParagraph(t.moveInFileWarning, warning: true),
      ],
      MoveInRefused(:final refusal) => [
        SettingsParagraph(t.moveInRefused, warning: true),
        SettingsParagraph(moveInReason(t, refusal.rule), warning: true),
        SettingsParagraph(t.moveInDetails(moveInDetails(refusal))),
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    return ZenPageScaffold(
      title: t.moveInTitle,
      body: ListView(
        children: [
          SettingsParagraph(t.moveInIntro),
          SettingsParagraph(t.moveInFileWarning, warning: true),
          SettingsParagraph(t.moveInServerNote),
          SettingsAction(
            label: t.moveInButton,
            variant: ZenButtonVariant.primary,
            onPressed: _busy || _result is MovedIn ? null : () => _choose(t),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: ZenProgressIndicator()),
            ),
          Semantics(liveRegion: true, child: Column(children: _outcome(t))),
        ],
      ),
    );
  }
}
