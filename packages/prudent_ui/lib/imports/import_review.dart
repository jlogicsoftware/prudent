import 'package:flutter/foundation.dart';

import '../generated/prudent/v1/imports.pb.dart';

/// A session and its held rows as the review screen shows them.
///
/// Immutable: every change makes a new value from what the server answered, so the figures on
/// screen are the server's, not a client tally that could drift. The one thing computed here is
/// whether the confirm button may be pressed, and it only restates the server's own refusals.
@immutable
class ImportReview {
  ImportReview({required this.session, required Iterable<ImportRow> rows})
    : rows = List.unmodifiable(rows);

  final ImportSession session;
  final List<ImportRow> rows;

  /// True while the session still holds rows that can be decided.
  bool get isOpen =>
      session.state == ImportSessionState.IMPORT_SESSION_STATE_PARSED ||
      session.state == ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED;

  List<ImportRow> get accepted => [
    for (final r in rows)
      if (r.status == ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED) r,
  ];

  /// Every duplicate, including those the user chose to import anyway.
  List<ImportRow> get duplicates => [
    for (final r in rows)
      if (r.status == ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE) r,
  ];

  List<ImportRow> get rejected => [
    for (final r in rows)
      if (r.status == ImportRowStatus.IMPORT_ROW_STATUS_REJECTED) r,
  ];

  /// What a commit would write: accepted rows and duplicates the user included.
  List<ImportRow> get writable => [for (final r in rows) if (writes(r)) r];

  static bool writes(ImportRow row) =>
      row.status == ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED ||
      (row.status == ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE && row.includeDuplicate);

  /// An expense has a negative amount. A rejected row has none and is never written.
  static bool isExpense(ImportRow row) => row.hasAmountMinor() && row.amountMinor.isNegative;

  /// The default category for [row]'s direction, or null when none is set.
  String? defaultFor(ImportRow row) {
    final id =
        isExpense(row) ? session.defaultExpenseCategoryId : session.defaultIncomeCategoryId;
    return id.isEmpty ? null : id;
  }

  /// The category [row] would be filed under: its own, else the session's default for its direction.
  String? effectiveCategory(ImportRow row) {
    if (row.hasCategoryId() && row.categoryId.isNotEmpty) return row.categoryId;
    return defaultFor(row);
  }

  /// How many rows to be written have neither a category of their own nor a default: the commit
  /// refuses the session while this is above zero (ADR-092).
  int get uncategorised => writable.where((r) => effectiveCategory(r) == null).length;

  /// The held rows and the server's count of accepted rows tell the same story. A mismatch means the
  /// client's rows are stale, and committing would be refused (409), so confirm waits for a reload.
  bool get countsAgree => writable.length == session.acceptedRows;

  bool get hasDestination => session.hasAccountId() && session.accountId.isNotEmpty;

  bool get canConfirm => isOpen && hasDestination && countsAgree && uncategorised == 0;

  /// What the commit confirms: exactly the accepted rows the server last counted.
  int get confirmedRows => session.acceptedRows;

  /// The review after one row decision: the row replaced and the three counts the server recomputed.
  ImportReview withRowDecision(UpdateImportRowResponse answer) {
    final updated = answer.row;
    return ImportReview(
      session:
          session.deepCopy()
            ..acceptedRows = answer.acceptedRows
            ..duplicateRows = answer.duplicateRows
            ..rejectedRows = answer.rejectedRows,
      rows: [for (final r in rows) if (r.rowNumber == updated.rowNumber) updated else r],
    );
  }

  /// The review after the defaults changed: the server answers the session without its rows.
  ImportReview withSession(ImportSession answer) => ImportReview(session: answer, rows: rows);
}
