package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.proto.v1.ImportRow;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.proto.v1.ListImportSessionsResponse;

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
    if (entity.accountId != null) {
      builder.setAccountId(entity.accountId.toString());
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
