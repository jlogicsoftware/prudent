package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import prudent.record.RecordEntity;

/**
 * Duplicate detection (M6, jlogicsoftware/prudent#75, ADR-091): the {@link ImportPreviewStage} that
 * keys every row of the session for its destination account and marks the rows whose key a ledger
 * record of that account already holds as {@link RowStatus#DUPLICATE}.
 *
 * <p><strong>What it does, in order.</strong> It clears every key (a repeated preview may be for
 * another account, and a key belongs to one account). With no destination account it stops there:
 * nothing can be a duplicate of nothing. Otherwise it keys every non-rejected row, whatever other
 * stages have already made of it, because a row another stage marked still occupies its occurrence
 * number, and then marks each still-ACCEPTED row whose key is already imported. It never un-marks a
 * row: the workflow resets duplicates before stages run, and a stage's result is its own.
 *
 * <p><strong>What it does not do.</strong> It does not collapse identical rows within one statement
 * (they are separate rows with occurrences 1, 2, ...), it does not look at records the user typed
 * by hand (they carry no key), and it does not know about a row that was pending in one export and
 * booked in the next (a changed description is a different fingerprint, so such a row is imported
 * again; ADR-091 states this as a limitation). The row carries a code and nothing else about why.
 */
@ApplicationScoped
public class ImportDuplicateStage implements ImportPreviewStage {

  /** The code on a row whose key a record of the destination account already holds. */
  public static final String ALREADY_IMPORTED = "duplicate.already_imported";

  @Inject ImportFormats formats;

  @Override
  public void apply(ImportSessionEntity session, List<ImportRowEntity> rows) {
    for (ImportRowEntity row : rows) {
      row.fingerprint = null;
      row.occurrence = null;
    }
    if (session.accountId == null) {
      return;
    }
    StatementImporter importer =
        formats
            .find(session.formatId)
            .orElseThrow(
                () ->
                    new IllegalStateException(
                        "No importer for the format of import session " + session.id + "."));

    List<ImportRowEntity> keyed = new ArrayList<>();
    for (ImportRowEntity row : rows) {
      if (row.status != RowStatus.REJECTED) {
        keyed.add(row);
      }
    }
    assignKeys(importer, session, keyed);

    Set<RowKey> imported =
        RecordEntity.importedKeys(
            session.userId,
            session.accountId,
            keyed.stream().map(row -> row.fingerprint).distinct().toList());
    for (ImportRowEntity row : keyed) {
      if (row.status == RowStatus.ACCEPTED
          && imported.contains(new RowKey(row.fingerprint, row.occurrence))) {
        row.status = RowStatus.DUPLICATE;
        row.duplicateCode = ALREADY_IMPORTED;
      }
    }
  }

  /**
   * Sets {@code fingerprint} and {@code occurrence} on each of {@code keyed}, which are in statement
   * order and none of which is rejected, by the scheme the importer's format calls for.
   */
  private static void assignKeys(
      StatementImporter importer, ImportSessionEntity session, List<ImportRowEntity> keyed) {
    if (importer.stableExternalId()) {
      for (ImportRowEntity row : keyed) {
        if (row.externalId == null) {
          throw new IllegalStateException(
              "Format " + session.formatId + " claims a stable identifier but row "
                  + row.rowNumber + " has none.");
        }
        RowKey key = RowFingerprints.stableIdKey(session.accountId, session.formatId, row.externalId);
        row.fingerprint = key.fingerprint();
        row.occurrence = key.occurrence();
      }
      return;
    }
    List<String> fingerprints =
        keyed.stream()
            .map(
                row ->
                    RowFingerprints.fingerprint(
                        session.accountId,
                        session.formatId,
                        session.currency,
                        new RowFingerprints.Fields(
                            row.transactionDate,
                            row.amountMinor,
                            row.description,
                            row.counterparty,
                            row.counterpartyAccount)))
            .toList();
    List<RowKey> keys = RowFingerprints.keys(fingerprints);
    for (int i = 0; i < keyed.size(); i++) {
      keyed.get(i).fingerprint = keys.get(i).fingerprint();
      keyed.get(i).occurrence = keys.get(i).occurrence();
    }
  }
}
