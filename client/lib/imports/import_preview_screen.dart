import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/imports.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../load_error_view.dart';
import '../providers.dart';
import 'import_ended_view.dart';
import 'import_failure.dart';
import 'import_failure_text.dart';
import 'import_failure_view.dart';
import 'import_group.dart';
import 'import_providers.dart';
import 'import_result_view.dart';
import 'import_review.dart';
import 'import_review_body.dart';
import 'import_row_form.dart';

/// The review of one import session (M6, jlogicsoftware/prudent#74): the rows that will be imported,
/// the duplicates, the rows that could not be read; a destination, default categories, a category
/// and note for each row; and the confirmation. After the commit the same page shows the result.
///
/// Leaving an open import by the page's own Back, the system's back gesture or the browser's asks
/// first and discards it (`PopScope` below). When the import is the ROOT page of a side pane, jZen
/// asks that `PopScope` for the pane's Close, Escape and a second detail replacing the pane too
/// (jZen#222, ADR-096). The real path is not that case: Accounts is the pane root and opens the
/// import from inside it, so the import is a nested page, and only Back reaches this guard; Escape
/// and a second detail dismiss the pane without asking and there is no Close button (jZenDev/jZen#226).
/// The prompt exists because a session holds rows for 24 hours and only a few may be open, and an
/// import nobody can find again is worse than one that was thrown away.
///
/// Whatever leaves without asking (those exits, and switching to another tab, which no guard can
/// stop) leaves the session open. Nothing is
/// discarded in `dispose` either: that would send a network call the user never agreed to, from a
/// widget that may have just committed. The session is left open and is found again under
/// "Unfinished imports" on the first step, as one left open by closing the app is (ADR-093, ADR-096).
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({super.key, required this.sessionId, required this.onBackToImport});

  final String sessionId;

  /// Shows the first step of the import again, for a session that ended and has nothing to review.
  final VoidCallback onBackToImport;

  @override
  ConsumerState<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  var _group = ImportGroup.accepted;
  var _working = 0;
  var _allowPop = false;

  ImportReviewNotifier get _notifier => ref.read(importReviewProvider(widget.sessionId).notifier);

  void _reload() => ref.invalidate(importReviewProvider(widget.sessionId));

  /// Runs one request. A refusal is shown in words and, when it means the session may have changed
  /// under us (409, 404), the session is read again so the screen shows what is true now.
  Future<bool> _run(Future<void> Function() action, String lead, {bool commit = false}) async {
    setState(() => _working++);
    try {
      await action();
      return true;
    } on ZenError catch (error) {
      final failure = ImportFailure.from(error);
      // A conflict or a missing session may mean it ended meanwhile; a lost answer to a commit may
      // mean it went through. Either way the screen reads the session again to show what is true.
      if (failure.shouldReload || (commit && failure.kind != ImportFailureKind.rule)) _reload();
      if (mounted) {
        final t = PrudentLocalizations.of(context);
        // A refusal that names rows (a category gone at the commit, say) says which, as the upload
        // screen's failure box does; the sentence alone would leave the user guessing.
        final rows = importFailureRows(t, failure);
        // A rule refusal at the commit means nothing was written (the sentence says so), so the
        // "may not have been written" lead of a lost answer would contradict it.
        final heading =
            commit && failure.kind == ImportFailureKind.rule ? '${t.importFailureTitle}.' : lead;
        showZenMessage(
          context,
          '$heading ${importFailureMessage(t, failure)}${rows == null ? '' : ' $rows.'}',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _working--);
    }
  }

  void _leave() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  Future<bool> _confirmDiscard({required bool leaving}) async {
    final t = PrudentLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(leaving ? t.importLeaveTitle : t.importDiscardTitle),
            content: Text(leaving ? t.importLeaveBody : t.importDiscardBody),
            actions: [
              ZenButton(
                label: leaving ? t.importStay : t.cancel,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx, false),
              ),
              ZenButton(
                label: leaving ? t.importLeave : t.importDiscardAction,
                variant: ZenButtonVariant.text,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
    );
    return yes == true;
  }

  Future<void> _discard({required bool leaving}) async {
    if (!await _confirmDiscard(leaving: leaving) || !mounted) return;
    final t = PrudentLocalizations.of(context);
    if (await _run(_notifier.discard, t.importDiscardFailed) && mounted) _leave();
  }

  void _editRow(ImportRow row) {
    final categories = ref.read(categoriesProvider).value ?? const [];
    showAdaptivePresentation<void>(
      context,
      builder:
          (_) => ImportRowForm(
            row: row,
            categories: categories,
            onSave: ({String? categoryId, String? note}) async {
              if (categoryId == null && note == null) return;
              try {
                await _notifier.decideRow(row.rowNumber, categoryId: categoryId, note: note);
              } on ZenError catch (error) {
                if (ImportFailure.from(error).shouldReload) _reload();
                rethrow;
              }
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    final review = ref.watch(importReviewProvider(widget.sessionId));
    final open = review.value?.isOpen ?? false;

    return PopScope(
      canPop: _allowPop || !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard(leaving: true);
      },
      child: ZenPageScaffold(
        title:
            review.value?.session.state == ImportSessionState.IMPORT_SESSION_STATE_COMMITTED
                ? t.importResultTitle
                : t.importPreviewTitle,
        actions: [
          if (open)
            ZenIconButton(
              icon: Icons.delete_outline,
              label: t.importDiscardAction,
              onPressed: _working > 0 ? null : () => _discard(leaving: false),
            ),
        ],
        body: review.when(
          loading: () => const Center(child: ZenProgressIndicator()),
          error: (error, stack) => _loadFailed(context, error, stack),
          data: (value) => _data(context, value),
        ),
      ),
    );
  }

  Widget _loadFailed(BuildContext context, Object error, StackTrace stack) {
    final t = PrudentLocalizations.of(context);
    final failure = ImportFailure.from(error);
    if (failure.kind == ImportFailureKind.notFound) {
      return ImportEndedView(
        title: t.importGoneTitle,
        body: t.importGoneBody,
        onBack: widget.onBackToImport,
      );
    }
    if (failure.kind == ImportFailureKind.network ||
        failure.kind == ImportFailureKind.unavailable ||
        failure.kind == ImportFailureKind.unexpected) {
      return LoadErrorView(
        message: t.importPreviewLoadError,
        error: error,
        stackTrace: stack,
        onRetry: _reload,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ImportFailureView(
        failure: failure,
        title: t.importFailureTitle,
        onRetry: _reload,
      ),
    );
  }

  Widget _data(BuildContext context, ImportReview review) {
    final t = PrudentLocalizations.of(context);
    switch (review.session.state) {
      case ImportSessionState.IMPORT_SESSION_STATE_COMMITTED:
        return ImportResultView(session: review.session);
      case ImportSessionState.IMPORT_SESSION_STATE_EXPIRED:
        return ImportEndedView(
          title: t.importExpiredTitle,
          body: t.importExpiredBody,
          onBack: widget.onBackToImport,
        );
      case ImportSessionState.IMPORT_SESSION_STATE_DISCARDED:
        return ImportEndedView(
          title: t.importDiscardedTitle,
          body: t.importDiscardedBody,
          onBack: widget.onBackToImport,
        );
      default:
        break;
    }

    final categories = ref.watch(categoriesProvider);
    final accounts = ref.watch(accountsProvider);
    return categories.when(
      loading: () => const Center(child: ZenProgressIndicator()),
      error:
          (error, stack) => LoadErrorView(
            message: t.categoriesLoadError,
            error: error,
            stackTrace: stack,
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
      data:
          (cats) => ImportReviewBody(
            review: review,
            accounts: accounts.value ?? const [],
            categories: cats,
            group: _group,
            working: _working > 0,
            onGroupChanged: (g) => setState(() => _group = g),
            onDestination:
                (id) => _run(() => _notifier.changeDestination(id), t.importFailureTitle),
            onDefaults:
                ({String? expenseCategoryId, String? incomeCategoryId}) => _run(
                  () => _notifier.setDefaults(
                    expenseCategoryId: expenseCategoryId,
                    incomeCategoryId: incomeCategoryId,
                  ),
                  t.importRowSaveFailed,
                ),
            onEditRow: _editRow,
            onIncludeDuplicate:
                (row, include) => _run(
                  () => _notifier.decideRow(row.rowNumber, includeDuplicate: include),
                  t.importRowSaveFailed,
                ),
            onConfirm: () => _run(_notifier.commit, t.importCommitFailed, commit: true),
            onReload: _reload,
          ),
    );
  }
}
