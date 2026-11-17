import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent_ui/privacy/privacy_actions.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../app/local_providers.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/confirm_step.dart';
import '../widgets/settings_action.dart';
import '../widgets/settings_heading.dart';
import '../widgets/settings_paragraph.dart';

/// Settings → Privacy and data in Prudent Local: the person's copy of everything, and erasure
/// (plan unit 9; the local counterpart of ADR-071).
///
/// - **The copy is a file the person picks the place of**, never the clipboard (ADR-100 T14:
///   clipboard managers, Universal Clipboard and Windows' cloud history reach other machines). It is
///   plaintext, and the page says so before the button.
/// - **"Erase this device's copy" says what remains** — the other devices, the folder, iCloud — and
///   never claims more (ADR-100 T24).
/// - **"Erase everywhere"** is jZen's (jZenDev/jZen#239): the transport cleans the shared place and
///   tells the other devices, which erase at their next sync. Irreversible, asked twice.
class LocalDataScreen extends ConsumerStatefulWidget {
  const LocalDataScreen({super.key});

  @override
  ConsumerState<LocalDataScreen> createState() => _LocalDataScreenState();
}

class _LocalDataScreenState extends ConsumerState<LocalDataScreen> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() step) async {
    setState(() => _busy = true);
    String? message;
    try {
      message = await step();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || message == null) return;
    showZenMessage(context, message);
  }

  Future<String?> _saveCopy(LocalLocalizations t) async {
    try {
      final file = await ref.read(privacyActionsProvider).exportFile();
      final saved = await ref.read(saveFileProvider)(file.name, file.bytes);
      return saved ? t.dataCopySaved : null;
    } on ZenError catch (error, stack) {
      // One line of classes, never the content (ADR-100 T21).
      developer.log(
        'data copy failed: ${error.runtimeType}',
        name: 'prudent',
        stackTrace: stack,
      );
      return t.dataCopyFailed;
    } on Exception catch (error, stack) {
      developer.log(
        'saving the data copy failed: ${error.runtimeType}',
        name: 'prudent',
        stackTrace: stack,
      );
      return t.dataCopyFailed;
    }
  }

  Future<void> _eraseHere(LocalLocalizations t) async {
    final go = await confirmStep(
      context,
      question: t.dataEraseConfirm,
      action: t.erase,
      cancel: t.cancel,
    );
    if (!go || !mounted) return;
    await _run(() async {
      final erased = await ref.read(localSessionProvider).eraseThisDevice();
      return erased is ZenSuccess ? t.dataErased : t.dataEraseFailed;
    });
  }

  Future<void> _eraseEverywhere(LocalLocalizations t) async {
    final first = await confirmStep(
      context,
      question: t.dataEverywhereHint,
      action: t.confirm,
      cancel: t.cancel,
    );
    if (!first || !mounted) return;
    final second = await confirmStep(
      context,
      question: t.dataEverywhereConfirm,
      action: t.dataEverywhereButton,
      cancel: t.cancel,
    );
    if (!second || !mounted) return;
    await _run(() async {
      final erased = await ref.read(localSessionProvider).eraseEverywhere();
      // On success the app shows that the data is gone everywhere; nothing more to say here.
      return erased is ZenSuccess ? null : t.dataEverywhereFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    final session = ref.watch(localSessionProvider);
    return ZenPageScaffold(
      title: t.dataTitle,
      body: ListView(
        children: [
          SettingsParagraph(t.dataIntro),
          SettingsHeading(t.dataCopyTitle),
          SettingsParagraph(t.dataCopyWarning, warning: true),
          SettingsAction(
            label: t.dataCopyButton,
            onPressed: _busy ? null : () => _run(() => _saveCopy(t)),
          ),
          SettingsHeading(t.dataEraseTitle),
          SettingsParagraph(t.dataEraseHint),
          SettingsAction(
            label: t.dataEraseButton,
            onPressed: _busy ? null : () => _eraseHere(t),
          ),
          SettingsHeading(t.dataEverywhereTitle),
          SettingsParagraph(t.dataEverywhereHint, warning: true),
          if (session.transport == null)
            SettingsParagraph(t.dataEverywhereNoSync),
          SettingsAction(
            label: t.dataEverywhereButton,
            onPressed: _busy ? null : () => _eraseEverywhere(t),
          ),
        ],
      ),
    );
  }
}
