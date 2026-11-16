import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;

import '../../generated/prudent_local/v1/imports.pb.dart';
import 'import_text.dart';

/// A session as the device holds it, answered as the wire's `ImportSession` — the server's
/// `ImportMapper`, field for field, so the shared import screens read either app's answer alike.
///
/// What never reaches the wire: the statement's identity token, a row's key (ADR-091: the digest is
/// personal data and never shown) and a commit plan. Rows are answered only where the server answers
/// them (a parse, a read of an open session, a preview).
abstract final class ImportMapper {
  static wire.ImportSession session(LocalImportSession s, {bool withRows = false}) {
    final out = wire.ImportSession(
      id: s.id,
      formatId: s.formatId,
      state: phase(s.phase),
      currency: s.currency,
      createdAtMs: s.createdAtMs,
      stateChangedAtMs: s.phaseChangedAtMs,
      expiresAtMs: s.expiresAtMs,
      acceptedRows: s.acceptedRows,
      duplicateRows: s.duplicateRows,
      rejectedRows: s.rejectedRows,
    );
    if (s.hasCommittedWritten()) {
      out
        ..committedWritten = s.committedWritten
        ..committedAlreadyImported = s.committedAlreadyImported;
    }
    if (s.hasAccountId()) out.accountId = s.accountId;
    if (s.hasDefaultExpenseCategoryId()) {
      out.defaultExpenseCategoryId = s.defaultExpenseCategoryId;
    }
    if (s.hasDefaultIncomeCategoryId()) out.defaultIncomeCategoryId = s.defaultIncomeCategoryId;
    if (withRows) out.rows.addAll([for (final r in s.rows) row(s.id, r)]);
    return out;
  }

  static wire.ImportRow row(String sessionId, LocalImportRow r) {
    final out = wire.ImportRow(
      sessionId: sessionId,
      rowNumber: r.rowNumber,
      status: status(r.kind),
      includeDuplicate: r.includeDuplicate,
    );
    if (r.rejectionCode.isNotEmpty) out.rejectionCode = r.rejectionCode;
    if (r.hasCategoryId()) out.categoryId = r.categoryId;
    if (r.hasNote()) out.note = r.note;
    if (r.hintCode.isNotEmpty) out.hintCode = r.hintCode;
    if (r.duplicateCode.isNotEmpty) out.duplicateCode = r.duplicateCode;
    if (r.hasTransactionDate()) out.transactionDate = r.transactionDate;
    if (r.hasBookingDate()) out.bookingDate = r.bookingDate;
    if (r.hasAmountMinor()) out.amountMinor = r.amountMinor;
    if (r.hasDescription()) out.description = ImportText.read(r.description);
    if (r.hasCounterparty()) out.counterparty = ImportText.read(r.counterparty);
    if (r.hasCounterpartyAccount()) {
      out.counterpartyAccount = ImportText.read(r.counterpartyAccount);
    }
    if (r.hasExternalId()) out.externalId = ImportText.read(r.externalId);
    return out;
  }

  static wire.ImportSessionState phase(ImportPhase phase) => switch (phase) {
    ImportPhase.IMPORT_PHASE_PARSED => wire.ImportSessionState.IMPORT_SESSION_STATE_PARSED,
    ImportPhase.IMPORT_PHASE_PREVIEWED => wire.ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED,
    ImportPhase.IMPORT_PHASE_COMMITTED => wire.ImportSessionState.IMPORT_SESSION_STATE_COMMITTED,
    ImportPhase.IMPORT_PHASE_DISCARDED => wire.ImportSessionState.IMPORT_SESSION_STATE_DISCARDED,
    ImportPhase.IMPORT_PHASE_EXPIRED => wire.ImportSessionState.IMPORT_SESSION_STATE_EXPIRED,
    _ => throw StateError('An import session is stored with no phase.'),
  };

  static wire.ImportRowStatus status(ImportRowKind kind) => switch (kind) {
    ImportRowKind.IMPORT_ROW_KIND_ACCEPTED => wire.ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED,
    ImportRowKind.IMPORT_ROW_KIND_DUPLICATE => wire.ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE,
    ImportRowKind.IMPORT_ROW_KIND_REJECTED => wire.ImportRowStatus.IMPORT_ROW_STATUS_REJECTED,
    _ => throw StateError('An import row is stored with no status.'),
  };
}
