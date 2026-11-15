import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../load_error_view.dart';
import '../providers.dart';
import 'import_failure.dart';
import 'import_failure_text.dart';
import 'import_providers.dart';
import 'import_result.dart';

/// The imports the user started and has not finished, each with a way to continue or discard it.
///
/// A session holds its rows for 24 hours and the server allows only a few open at once, so this is
/// both the way back into an import left half-way and the way out of a "too many open imports"
/// refusal. Shows nothing at all when there are none.
class OpenImportSessions extends ConsumerWidget {
  const OpenImportSessions({super.key, required this.onContinue});

  /// Opens the review of the session with this id.
  final void Function(String sessionId) onContinue;

  Future<void> _discard(BuildContext context, WidgetRef ref, ImportSession session) async {
    final t = PrudentLocalizations.of(context);
    try {
      final result = await ref.read(prudentRepositoryProvider).discardImportSession(session.id);
      unwrapImportResult(result);
      ref.invalidate(openImportSessionsProvider);
    } on ZenError catch (error) {
      if (!context.mounted) return;
      // A refusal that means "already gone" is reflected by reloading the list.
      final failure = ImportFailure.from(error);
      if (failure.shouldReload) ref.invalidate(openImportSessionsProvider);
      showZenMessage(context, '${t.importDiscardFailed} ${importFailureMessage(t, failure)}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final sessions = ref.watch(openImportSessionsProvider);
    return sessions.when(
      loading: () => const SizedBox.shrink(),
      error:
          (error, stack) => LoadErrorView(
            message: t.importOpenSessionsLoadError,
            error: error,
            stackTrace: stack,
            onRetry: () => ref.invalidate(openImportSessionsProvider),
            compact: true,
          ),
      data: (open) {
        if (open.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(t.importOpenSessionsTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final session in open)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.importOpenSessionTitle),
                    Text(
                      t.importOpenSessionFigures(
                        session.acceptedRows,
                        session.duplicateRows,
                        session.rejectedRows,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ZenButton(
                          label: t.importContinue,
                          variant: ZenButtonVariant.secondary,
                          onPressed: () => onContinue(session.id),
                        ),
                        ZenButton(
                          label: t.importDiscardAction,
                          variant: ZenButtonVariant.text,
                          onPressed: () => _discard(context, ref, session),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
