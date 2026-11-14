package prudent.imports;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * The {@code prudent_import_row} table — one normalised statement row held while its session is
 * PARSED or PREVIEWED (M6, jlogicsoftware/prudent#72, ADR-089). Active-record Panache entity.
 *
 * <p>The row carries personal data, so {@link #deleteOf} runs whenever a session ends. Nothing here
 * stores the statement: every field is something an importer parsed out of it.
 */
@Entity
@Table(name = "prudent_import_row")
public class ImportRowEntity extends PanacheEntityBase {

  @Id public UUID id;

  @Column(name = "session_id", nullable = false)
  public UUID sessionId;

  @Column(name = "user_id", nullable = false)
  public UUID userId;

  @Column(name = "row_number", nullable = false)
  public int rowNumber;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  public RowStatus status;

  /** A rule code, set exactly when {@link #status} is {@link RowStatus#REJECTED}. */
  @Column(name = "rejection_code")
  public String rejectionCode;

  @Column(name = "transaction_date")
  public LocalDate transactionDate;

  @Column(name = "booking_date")
  public LocalDate bookingDate;

  /** Signed minor units; {@code null} only on a rejected row. */
  @Column(name = "amount_minor")
  public Long amountMinor;

  public String description;

  public String counterparty;

  @Column(name = "counterparty_account")
  public String counterpartyAccount;

  @Column(name = "external_id")
  public String externalId;

  /**
   * The row's duplicate-detection key ({@link RowKey}), set by the preview for the session's
   * destination account and {@code null} before it, on a rejected row, and when no account is
   * chosen. A digest, never statement text. The commit copies it onto the ledger record.
   */
  @Column(name = "fingerprint")
  public String fingerprint;

  /** The second half of the key: which of the rows with this fingerprint this one is (1-based). */
  @Column(name = "occurrence")
  public Integer occurrence;

  /**
   * Why a row is a duplicate: a stable code ({@link ImportDuplicateStage#ALREADY_IMPORTED}), never
   * content. Set only on a {@link RowStatus#DUPLICATE} row, and cleared when the row stops being one.
   */
  @Column(name = "duplicate_code")
  public String duplicateCode;

  /** The rows of one session, in statement order. Ownership is part of the lookup. */
  public static List<ImportRowEntity> ofSession(UUID userId, UUID sessionId) {
    return list("userId = ?1 and sessionId = ?2 order by rowNumber", userId, sessionId);
  }

  /** Every row the caller holds, in session then statement order — for the data export. */
  public static List<ImportRowEntity> listOwnedBy(UUID userId) {
    return list("userId = ?1 order by sessionId, rowNumber", userId);
  }

  /** Deletes the rows of one session; the answer is how many went. */
  public static long deleteOf(UUID userId, UUID sessionId) {
    return delete("userId = ?1 and sessionId = ?2", userId, sessionId);
  }
}
