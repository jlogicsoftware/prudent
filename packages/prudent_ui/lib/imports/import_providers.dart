import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart';
import '../providers.dart';
import 'import_result.dart';
import 'import_review.dart';
import 'statement_format.dart';

/// The sessions still waiting for a decision (parsed or previewed), newest first. They are how an
/// import left half-way is resumed or discarded, and what a "too many open imports" refusal asks the
/// user to clear.
final openImportSessionsProvider = FutureProvider.autoDispose<List<ImportSession>>(retry: _never, (ref) async {
  final response = unwrapImportResult(await ref.watch(prudentRepositoryProvider).listImportSessions());
  return [
    for (final s in response.sessions)
      if (s.state == ImportSessionState.IMPORT_SESSION_STATE_PARSED ||
          s.state == ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED)
        s,
  ];
});

/// Uploads a statement and opens a session (the parse phase). The bytes go to the server once and
/// are not kept here; the answer is a session id the review screen loads by.
class ImportStarter {
  ImportStarter(this._ref);

  final Ref _ref;

  /// Throws the server's error as it came (a rule refusal, a 409 for too many sessions), for
  /// `ImportFailure.from` to classify.
  Future<ImportSession> start({required Uint8List bytes, required String accountId}) async {
    final session = unwrapImportResult(
      await _ref
          .read(prudentRepositoryProvider)
          .createImportSession(
            CreateImportSessionRequest(
              formatId: erstePlCsvFormatId,
              content: bytes,
              accountId: accountId,
            ),
          ),
    );
    _ref.invalidate(openImportSessionsProvider);
    return session;
  }
}

final importStarterProvider = Provider<ImportStarter>(ImportStarter.new);

/// One import session under review: the session, its held rows, and the decisions made on them.
///
/// Every method sends the decision to the server and takes the figures from its answer; none keeps
/// a tally of its own. A method that fails throws the server's error and leaves the state as it was,
/// so the screen still shows what the server last confirmed.
class ImportReviewNotifier extends AsyncNotifier<ImportReview> {
  ImportReviewNotifier(this.sessionId);

  final String sessionId;

  @override
  Future<ImportReview> build() async {
    final repository = ref.read(prudentRepositoryProvider);
    var session = unwrapImportResult(await repository.getImportSession(sessionId));
    if (session.state == ImportSessionState.IMPORT_SESSION_STATE_PARSED) {
      // A session fresh from the upload is classified here, once: duplicates are only known after
      // a preview, and the review shows them.
      session = unwrapImportResult(
        await repository.previewImportSession(sessionId, PreviewImportSessionRequest()),
      );
    }
    return ImportReview(session: session, rows: session.rows);
  }

  ImportReview get _current => state.requireValue;

  /// Chooses another destination account. The rows are classified again for it (duplicates are
  /// account specific), so what the user decided about them is reset by the server.
  Future<void> changeDestination(String accountId) async {
    final session = unwrapImportResult(
      await ref
          .read(prudentRepositoryProvider)
          .previewImportSession(sessionId, PreviewImportSessionRequest(accountId: accountId)),
    );
    state = AsyncData(ImportReview(session: session, rows: session.rows));
  }

  /// Decides one row. Only the fields given change; an empty [categoryId] or [note] clears.
  Future<void> decideRow(
    int rowNumber, {
    String? categoryId,
    String? note,
    bool? includeDuplicate,
  }) async {
    final answer = unwrapImportResult(
      await ref
          .read(prudentRepositoryProvider)
          .updateImportRow(
            sessionId,
            rowNumber,
            UpdateImportRowRequest(
              categoryId: categoryId,
              note: note,
              includeDuplicate: includeDuplicate,
            ),
          ),
    );
    state = AsyncData(_current.withRowDecision(answer));
  }

  /// Sets the default category for expenses and/or income. Only the fields given change; an empty
  /// string clears one.
  Future<void> setDefaults({String? expenseCategoryId, String? incomeCategoryId}) async {
    final session = unwrapImportResult(
      await ref
          .read(prudentRepositoryProvider)
          .setImportDefaults(
            sessionId,
            SetImportDefaultsRequest(
              defaultExpenseCategoryId: expenseCategoryId,
              defaultIncomeCategoryId: incomeCategoryId,
            ),
          ),
    );
    state = AsyncData(_current.withSession(session));
  }

  /// Writes the session to the ledger, confirming exactly the accepted rows the server last
  /// counted. On success the state becomes the committed session (counts only, no rows) and
  /// everything calculated from the ledger is read again.
  Future<void> commit() async {
    final confirmed = _current.confirmedRows;
    final session = unwrapImportResult(
      await ref
          .read(prudentRepositoryProvider)
          .commitImportSession(
            sessionId,
            CommitImportSessionRequest(confirmedAcceptedRows: confirmed),
          ),
    );
    state = AsyncData(ImportReview(session: session, rows: const []));
    _invalidateLedgerFigures();
  }

  /// Throws the session away; nothing was written.
  Future<void> discard() async {
    final session = unwrapImportResult(
      await ref.read(prudentRepositoryProvider).discardImportSession(sessionId),
    );
    state = AsyncData(ImportReview(session: session, rows: const []));
    ref.invalidate(openImportSessionsProvider);
  }

  void _invalidateLedgerFigures() {
    // Records were written to one account: its balance, the lists, the budgets, the analytics and the
    // free money for goals all moved. Same set an account's deletion with its records refreshes.
    ref.invalidate(accountsProvider);
    ref.invalidate(recordsProvider);
    ref.invalidate(budgetSummaryProvider);
    ref.invalidate(spendByCategoryProvider);
    ref.invalidate(spendByPeriodProvider);
    ref.invalidate(goalFreeMoneyProvider);
    ref.invalidate(openImportSessionsProvider);
  }
}

/// No automatic retry: a refusal here (a rule, a 404 for an expired session) is an answer, and
/// retrying it with a back-off would leave the screen spinning where it should explain. The screen's
/// own "Try again" asks again.
final importReviewProvider = AsyncNotifierProvider.autoDispose
    .family<ImportReviewNotifier, ImportReview, String>(
      ImportReviewNotifier.new,
      retry: _never,
    );

Duration? _never(int retryCount, Object error) => null;
