package prudent;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for the duplicate-detection key (V20261114110000, ADR-091), through plain SQL
 * on the owner connection so it reads what the schema itself refuses. The unique index is what
 * makes a second commit of the same statement row fail instead of doubling the ledger.
 */
@QuarkusTest
class ImportFingerprintSchemaTest {

  private static final String KEY = "v1:" + "a".repeat(64);

  @Inject DataSource dataSource;

  private UUID account;
  private UUID otherAccount;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    otherAccount = PrudentTest.seedAccount(PrudentTest.ALICE, "Other", "PLN");
  }

  private void insertRecord(UUID accountId, String fingerprint, Integer occurrence)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_record (id, user_id, title, amount_minor, currency,"
                    + " record_date, account_id, import_fingerprint, import_occurrence)"
                    + " VALUES (?, ?, 'Imported', -1, 'PLN', '2026-10-01', ?, ?, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setObject(3, accountId);
      insert.setObject(4, fingerprint);
      insert.setObject(5, occurrence);
      insert.executeUpdate();
    }
  }

  private void assertRefusedBy(String constraint, ThrowingRunnable action) {
    SQLException refused = assertThrows(SQLException.class, action::run);
    assertTrue(refused.getMessage().contains(constraint), refused.getMessage());
  }

  @FunctionalInterface
  private interface ThrowingRunnable {
    void run() throws SQLException;
  }

  @Test
  void aStatementRowCanBeWrittenIntoAnAccountOnce() throws Exception {
    insertRecord(account, KEY, 1);

    assertRefusedBy("prudent_record_import_key_unique", () -> insertRecord(account, KEY, 1));
  }

  @Test
  void theSameFingerprintWithAnotherOccurrenceOrAccountIsAnotherRow() throws Exception {
    insertRecord(account, KEY, 1);
    insertRecord(account, KEY, 2);
    insertRecord(otherAccount, KEY, 1);
  }

  @Test
  void recordsThatWereNotImportedNeverCollide() throws Exception {
    insertRecord(account, null, null);
    insertRecord(account, null, null);
  }

  @Test
  void theKeyTravelsTogetherAndHasTheRightShape() {
    assertRefusedBy("prudent_record_import_key_paired", () -> insertRecord(account, KEY, null));
    assertRefusedBy("prudent_record_import_key_paired", () -> insertRecord(account, null, 1));
    assertRefusedBy("prudent_record_import_occurrence_positive", () -> insertRecord(account, KEY, 0));
    assertRefusedBy(
        "prudent_record_import_fingerprint_shape", () -> insertRecord(account, "not a digest", 1));
    assertRefusedBy(
        "prudent_record_import_fingerprint_shape",
        () -> insertRecord(account, "v1:" + "A".repeat(64), 1));
  }

  @Test
  void anImportRowsKeyIsCheckedAndNeverOnARejectedRow() throws Exception {
    UUID session = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_import_session (id, user_id, format_id, state, currency,"
                    + " created_at, state_changed_at, expires_at)"
                    + " VALUES (?, ?, 'f', 'PARSED', 'PLN', now(), now(), now() + interval '1 day')")) {
      insert.setObject(1, session);
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.executeUpdate();
    }

    assertRefusedBy(
        "prudent_import_row_key_not_rejected",
        () -> insertRow(session, 1, "REJECTED", "x.y", KEY, 1, null));
    assertRefusedBy(
        "prudent_import_row_key_paired", () -> insertRow(session, 2, "ACCEPTED", null, KEY, null, null));
    assertRefusedBy(
        "prudent_import_row_duplicate_code_only_on_duplicate",
        () -> insertRow(session, 3, "ACCEPTED", null, KEY, 1, "duplicate.already_imported"));
    insertRow(session, 4, "DUPLICATE", null, KEY, 1, "duplicate.already_imported");
  }

  private void insertRow(
      UUID session, int number, String status, String rejection, String fingerprint,
      Integer occurrence, String duplicateCode)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_import_row (id, session_id, user_id, row_number, status,"
                    + " rejection_code, transaction_date, amount_minor, fingerprint, occurrence,"
                    + " duplicate_code) VALUES (?, ?, ?, ?, ?, ?, '2026-10-01', -1, ?, ?, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, session);
      insert.setObject(3, UUID.fromString(PrudentTest.ALICE));
      insert.setInt(4, number);
      insert.setString(5, status);
      insert.setString(6, rejection);
      insert.setObject(7, fingerprint);
      insert.setObject(8, occurrence);
      insert.setString(9, duplicateCode);
      insert.executeUpdate();
    }
  }
}
