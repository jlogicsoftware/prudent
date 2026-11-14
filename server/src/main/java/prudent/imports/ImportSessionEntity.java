package prudent.imports;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.LockModeType;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;
import prudent.error.PrudentException;

/**
 * The {@code prudent_import_session} table — one statement import in progress or finished (M6,
 * jlogicsoftware/prudent#72, ADR-089). Active-record Panache entity.
 *
 * <p><strong>Not a record.</strong> Nothing that computes a balance or an analytics total reads this
 * table or {@link ImportRowEntity}. Rows reach the ledger only through
 * {@link ImportCommitter}, once, from the PREVIEWED state.
 *
 * <p>There is no delete method: a session ends by changing state, its rows are deleted, and only the
 * erasure cascade removes the session row itself.
 */
@Entity
@Table(name = "prudent_import_session")
public class ImportSessionEntity extends PanacheEntityBase {

  /** Server-minted. A create request carries no id. */
  @Id public UUID id;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(name = "format_id", nullable = false)
  public String formatId;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public ImportState state = ImportState.PARSED;

  /** The destination account, or {@code null} until chosen. No foreign key; see the migration. */
  @Column(name = "account_id")
  public UUID accountId;

  // char(3), matching the migration. JdbcTypeCode tells Hibernate's schema validation to expect
  // CHAR.
  @JdbcTypeCode(SqlTypes.CHAR)
  @Column(nullable = false, length = 3)
  public String currency;

  /**
   * The importer's identity token for the statement's own account ({@link
   * ParsedStatement#identityOf}), or {@code null} for a format without one. Kept only while the
   * session is open so the destination can be re-checked each time it changes; cleared when the
   * session ends and never sent over the wire.
   */
  @JdbcTypeCode(SqlTypes.CHAR)
  @Column(name = "statement_identity", length = 64)
  public String statementIdentity;

  @Column(name = "created_at", nullable = false)
  public Instant createdAt;

  @Column(name = "state_changed_at", nullable = false)
  public Instant stateChangedAt;

  @Column(name = "expires_at", nullable = false)
  public Instant expiresAt;

  @Column(name = "accepted_rows", nullable = false)
  public int acceptedRows;

  @Column(name = "duplicate_rows", nullable = false)
  public int duplicateRows;

  @Column(name = "rejected_rows", nullable = false)
  public int rejectedRows;

  /**
   * How many records the commit wrote, set exactly when the session is COMMITTED. Kept (with
   * {@link #committedAlreadyImported}) so a retry of the same commit can be answered with the same
   * result after the rows are gone (ADR-092).
   */
  @Column(name = "committed_written")
  public Integer committedWritten;

  /** How many accepted rows the commit found already imported; see {@link #committedWritten}. */
  @Column(name = "committed_already_imported")
  public Integer committedAlreadyImported;

  /**
   * The category a row of negative amount gets when it has none of its own; the caller's, active
   * and able to file expenses when set, re-checked at commit. {@code null} when not set; cleared
   * when the session ends. No foreign key, like {@code accountId}.
   */
  @Column(name = "default_expense_category_id")
  public UUID defaultExpenseCategoryId;

  /** As {@link #defaultExpenseCategoryId}, for a row of positive amount. */
  @Column(name = "default_income_category_id")
  public UUID defaultIncomeCategoryId;

  /** The default category for a row of this sign, or {@code null}. */
  public UUID defaultCategoryFor(long amountMinor) {
    return amountMinor < 0 ? defaultExpenseCategoryId : defaultIncomeCategoryId;
  }

  /**
   * Moves the session to {@code target}, or refuses (409) if {@link ImportState} does not allow it
   * from the current state. The only writer of {@link #state} after creation.
   */
  public void transitionTo(ImportState target, Instant at) {
    if (!state.canMoveTo(target)) {
      throw PrudentException.conflict(
          "An import session that is " + state + " cannot be made " + target + ".");
    }
    state = target;
    stateChangedAt = at;
  }

  /** Whether the session can no longer be previewed or committed at {@code now}. */
  public boolean isDue(Instant now) {
    return !expiresAt.isAfter(now);
  }

  /**
   * Recounts the three row classes from {@code rows}, the only writer of those counts. Called after
   * rows are first saved and after a preview stage may have reclassified some.
   */
  public void recount(List<ImportRowEntity> rows) {
    // A duplicate the user chose to include is written, so it is counted with the accepted rows
    // (what the commit confirms) and not with the duplicates left out (ADR-092).
    acceptedRows = (int) rows.stream().filter(ImportRowEntity::isWritable).count();
    duplicateRows =
        (int)
            rows.stream()
                .filter(r -> r.status == RowStatus.DUPLICATE && !r.includeDuplicate)
                .count();
    rejectedRows = count(rows, RowStatus.REJECTED);
  }

  private static int count(List<ImportRowEntity> rows, RowStatus status) {
    return (int) rows.stream().filter(row -> row.status == status).count();
  }

  /**
   * The caller's newest {@code limit} sessions, optionally of one state — what the list route
   * serves, so one user's history cannot make a response unbounded.
   */
  public static List<ImportSessionEntity> listRecent(UUID userId, ImportState state, int limit) {
    if (state == null) {
      return find("userId = ?1 order by createdAt desc, id", userId).page(0, limit).list();
    }
    return find("userId = ?1 and state = ?2 order by createdAt desc, id", userId, state)
        .page(0, limit)
        .list();
  }

  /**
   * How many sessions the caller has open (PARSED or PREVIEWED) that have not yet run out of time.
   * One that is due counts for nothing: it is already as good as expired, and the sweep has merely
   * not reached it.
   */
  public static long countOpen(UUID userId, Instant now) {
    return count(
        "userId = ?1 and state in (?2) and expiresAt > ?3",
        userId,
        List.of(ImportState.PARSED, ImportState.PREVIEWED),
        now);
  }

  /** Every session the caller has, newest first and then by id — the data export, unbounded. */
  public static List<ImportSessionEntity> listOwnedBy(UUID userId, ImportState state) {
    if (state == null) {
      return list("userId = ?1 order by createdAt desc, id", userId);
    }
    return list("userId = ?1 and state = ?2 order by createdAt desc, id", userId, state);
  }

  /** One session, but only if the caller owns it — ownership is part of the lookup. */
  public static ImportSessionEntity findOwned(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId).firstResult();
  }

  /**
   * One session, but only if the caller owns it, locked for the rest of the transaction. Every
   * phase change takes this first, so two requests cannot both read PREVIEWED and both commit.
   */
  public static ImportSessionEntity findOwnedForUpdate(UUID userId, UUID id) {
    return find("id = ?1 and userId = ?2", id, userId)
        .withLock(LockModeType.PESSIMISTIC_WRITE)
        .firstResult();
  }

  /**
   * Sessions still holding rows whose expiry has passed, locked and skipping any another
   * transaction holds, so the sweep never waits on a request in flight and never races it.
   */
  public static List<ImportSessionEntity> lockDue(Instant now) {
    return getEntityManager()
        .createQuery(
            "from ImportSessionEntity s where s.state in (?1) and s.expiresAt <= ?2 order by s.id",
            ImportSessionEntity.class)
        .setParameter(1, List.of(ImportState.PARSED, ImportState.PREVIEWED))
        .setParameter(2, now)
        .setLockMode(LockModeType.PESSIMISTIC_WRITE)
        .setHint("jakarta.persistence.lock.timeout", -2)
        .getResultList();
  }
}
