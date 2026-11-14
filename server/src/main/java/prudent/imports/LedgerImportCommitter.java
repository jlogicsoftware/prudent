package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import prudent.account.AccountEntity;
import prudent.error.PrudentException;
import prudent.record.RecordEntity;
import prudent.record.RecordWriter;

/**
 * The real commit (M6, jlogicsoftware/prudent#76, ADR-092): turns the writable rows of a PREVIEWED
 * session into ordinary ledger records, once.
 *
 * <p><strong>Everything runs in the workflow's one transaction</strong> (this class starts none),
 * so any failure, in any row, rolls back every record already written for the session and leaves it
 * PREVIEWED with its rows.
 *
 * <p><strong>Order of work.</strong> (1) Lock the destination account's row. Two commits into one
 * account queue here, so the second reads what the first committed. (2) Refuse, before writing
 * anything, a session in which a row has neither its own category nor a default for its direction. (3) Re-read which keys the account already
 * holds ({@link RecordEntity#importedKeys}); a row whose key is held is {@code alreadyImported},
 * not an error, and is not written. (4) Write each remaining row through {@link RecordWriter} (the
 * same validation, currency and category rules as a typed record) and copy the row's key onto it.
 * (5) Write the rows the user chose to include although they were marked DUPLICATE, each under the
 * next free occurrence of its fingerprint, so the unique index is never asked to refuse them.
 *
 * <p>Records an import writes differ from hand-typed ones only by the key columns
 * ({@code import_fingerprint}, {@code import_occurrence}). Own-account transfer rows are ordinary
 * records of the destination account: no leg is invented in the other account (ADR-092).
 */
@ApplicationScoped
public class LedgerImportCommitter implements ImportCommitter {

  /** The title a record gets when its statement row has no description at all. */
  static final String FALLBACK_TITLE = "Imported transaction";

  @Inject RecordWriter writer;

  @Override
  public CommitResult commit(ImportSessionEntity session, List<ImportRowEntity> accepted) {
    AccountEntity account = AccountEntity.findOwnedForUpdate(session.userId, session.accountId);
    if (account == null) {
      throw PrudentException.conflict("The destination account no longer exists.");
    }
    if (accepted.isEmpty()) {
      // Nothing to write (every row was already imported, or none is wanted): a valid commit.
      return new CommitResult(0, 0);
    }
    long uncategorised =
        accepted.stream()
            .filter(row -> categoryOf(session, row) == null)
            .count();
    if (uncategorised > 0) {
      throw PrudentException.conflict(
          uncategorised
              + " row(s) have no category yet. Choose a category for every row, or a default"
              + " category for expenses and for income, before committing.");
    }
    for (ImportRowEntity row : accepted) {
      if (row.fingerprint == null || row.occurrence == null) {
        // A PREVIEWED session with a destination always has keys; a row without one would be
        // written unrecognisable, so it is a bug, not a user error.
        throw new IllegalStateException(
            "Row " + row.rowNumber + " of import session " + session.id + " has no key.");
      }
    }

    Set<RowKey> held =
        new HashSet<>(
            RecordEntity.importedKeys(
                session.userId,
                session.accountId,
                accepted.stream().map(row -> row.fingerprint).distinct().toList()));

    int written = 0;
    int alreadyImported = 0;
    List<ImportRowEntity> forced = new ArrayList<>();
    for (ImportRowEntity row : accepted) {
      if (row.includeDuplicate) {
        forced.add(row);
        continue;
      }
      RowKey key = new RowKey(row.fingerprint, row.occurrence);
      if (held.contains(key)) {
        alreadyImported++;
        continue;
      }
      write(session, row, row.occurrence);
      held.add(key);
      written++;
    }

    // Forced rows last, so the next free occurrence also steps over the rows written just above.
    Map<String, Integer> highest = new HashMap<>();
    for (RowKey key : held) {
      highest.merge(key.fingerprint(), key.occurrence(), Math::max);
    }
    for (ImportRowEntity row : forced) {
      int occurrence = highest.merge(row.fingerprint, 1, (old, one) -> old + 1);
      write(session, row, occurrence);
      written++;
    }
    RecordEntity.getEntityManager().flush();
    return new CommitResult(written, alreadyImported);
  }

  private void write(ImportSessionEntity session, ImportRowEntity row, int occurrence) {
    RecordEntity record = new RecordEntity();
    record.id = UUID.randomUUID();
    record.userId = session.userId;
    try {
      writer.apply(
          record,
          session.userId,
          titleOf(row),
          row.amountMinor,
          row.transactionDate.toString(),
          categoryOf(session, row).toString(),
          session.accountId.toString(),
          session.currency,
          row.counterparty,
          row.note);
    } catch (PrudentException refused) {
      // The writer's message names an account or category the user owns, never statement text.
      throw PrudentException.conflict(
          "Row " + row.rowNumber + " cannot be written: " + refused.getMessage());
    }
    record.importFingerprint = row.fingerprint;
    record.importOccurrence = occurrence;
    record.persist();
  }

  /**
   * The category a row is written under: its own, else the session's default for the row's
   * direction, else {@code null}. Either is validated by {@link RecordWriter} at the write.
   */
  private static UUID categoryOf(ImportSessionEntity session, ImportRowEntity row) {
    return row.categoryId != null ? row.categoryId : session.defaultCategoryFor(row.amountMinor);
  }

  private static String titleOf(ImportRowEntity row) {
    if (row.description != null && !row.description.isBlank()) {
      return row.description;
    }
    if (row.counterparty != null && !row.counterparty.isBlank()) {
      return row.counterparty;
    }
    return FALLBACK_TITLE;
  }
}
