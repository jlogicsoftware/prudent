package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.proto.v1.ImportRow;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.proto.v1.ListImportSessionsResponse;
import prudent.proto.v1.UpdateImportRowResponse;

/** Maps {@link ImportSessionEntity} and {@link ImportRowEntity} to their wire protos. */
@ApplicationScoped
public class ImportMapper {

  /** A session with no rows — the list and export shape. */
  public ImportSession toProto(ImportSessionEntity entity) {
    return toProto(entity, List.of());
  }

  /** A session with its held rows, in the order given. */
  public ImportSession toProto(ImportSessionEntity entity, List<ImportRowEntity> rows) {
    ImportSession.Builder builder =
        ImportSession.newBuilder()
            .setId(entity.id.toString())
            .setFormatId(entity.formatId)
            .setState(toWire(entity.state))
            .setCurrency(entity.currency)
            .setCreatedAtMs(entity.createdAt.toEpochMilli())
            .setStateChangedAtMs(entity.stateChangedAt.toEpochMilli())
            .setExpiresAtMs(entity.expiresAt.toEpochMilli())
            .setAcceptedRows(entity.acceptedRows)
            .setDuplicateRows(entity.duplicateRows)
            .setRejectedRows(entity.rejectedRows);
    if (entity.committedWritten != null) {
      builder.setCommittedWritten(entity.committedWritten);
      builder.setCommittedAlreadyImported(entity.committedAlreadyImported);
    }
    if (entity.accountId != null) {
      builder.setAccountId(entity.accountId.toString());
    }
    if (entity.defaultExpenseCategoryId != null) {
      builder.setDefaultExpenseCategoryId(entity.defaultExpenseCategoryId.toString());
    }
    if (entity.defaultIncomeCategoryId != null) {
      builder.setDefaultIncomeCategoryId(entity.defaultIncomeCategoryId.toString());
    }
    rows.forEach(row -> builder.addRows(toProto(row)));
    return builder.build();
  }

  public ImportRow toProto(ImportRowEntity entity) {
    ImportRow.Builder builder =
        ImportRow.newBuilder()
            .setSessionId(entity.sessionId.toString())
            .setRowNumber(entity.rowNumber)
            .setStatus(toWire(entity.status));
    if (entity.rejectionCode != null) {
      builder.setRejectionCode(entity.rejectionCode);
    }
    builder.setIncludeDuplicate(entity.includeDuplicate);
    if (entity.categoryId != null) {
      builder.setCategoryId(entity.categoryId.toString());
    }
    if (entity.note != null) {
      builder.setNote(entity.note);
    }
    if (entity.hintCode != null) {
      builder.setHintCode(entity.hintCode);
    }
    if (entity.duplicateCode != null) {
      builder.setDuplicateCode(entity.duplicateCode);
    }
    if (entity.transactionDate != null) {
      builder.setTransactionDate(entity.transactionDate.toString());
    }
    if (entity.bookingDate != null) {
      builder.setBookingDate(entity.bookingDate.toString());
    }
    if (entity.amountMinor != null) {
      builder.setAmountMinor(entity.amountMinor);
    }
    if (entity.description != null) {
      builder.setDescription(entity.description);
    }
    if (entity.counterparty != null) {
      builder.setCounterparty(entity.counterparty);
    }
    if (entity.counterpartyAccount != null) {
      builder.setCounterpartyAccount(entity.counterpartyAccount);
    }
    if (entity.externalId != null) {
      builder.setExternalId(entity.externalId);
    }
    return builder.build();
  }

  /** The light answer to a row decision: the row and the session's counts. */
  public UpdateImportRowResponse toRowResponse(ImportSessionEntity session, ImportRowEntity row) {
    return UpdateImportRowResponse.newBuilder()
        .setRow(toProto(row))
        .setAcceptedRows(session.acceptedRows)
        .setDuplicateRows(session.duplicateRows)
        .setRejectedRows(session.rejectedRows)
        .build();
  }

  public ListImportSessionsResponse toListResponse(List<ImportSessionEntity> entities) {
    ListImportSessionsResponse.Builder builder = ListImportSessionsResponse.newBuilder();
    entities.forEach(entity -> builder.addSessions(toProto(entity)));
    return builder.build();
  }

  static ImportSessionState toWire(ImportState state) {
    return switch (state) {
      case PARSED -> ImportSessionState.IMPORT_SESSION_STATE_PARSED;
      case PREVIEWED -> ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED;
      case COMMITTED -> ImportSessionState.IMPORT_SESSION_STATE_COMMITTED;
      case DISCARDED -> ImportSessionState.IMPORT_SESSION_STATE_DISCARDED;
      case EXPIRED -> ImportSessionState.IMPORT_SESSION_STATE_EXPIRED;
    };
  }

  static ImportRowStatus toWire(RowStatus status) {
    return switch (status) {
      case ACCEPTED -> ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED;
      case DUPLICATE -> ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE;
      case REJECTED -> ImportRowStatus.IMPORT_ROW_STATUS_REJECTED;
    };
  }
}
