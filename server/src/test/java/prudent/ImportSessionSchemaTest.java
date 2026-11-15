package prudent;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * Migration coverage for {@code prudent_import_session} and {@code prudent_import_row}
 * (V20261114090000, ADR-089): the structural invariants hold in the database itself, against a writer
 * that skips the workflow. Plain SQL through the owner connection; each refusal is matched by
 * CONSTRAINT NAME so a test cannot pass on an unrelated error.
 */
@QuarkusTest
class ImportSessionSchemaTest {

  @Inject DataSource dataSource;

  @BeforeEach
  void clean() {
    PrudentTest.reset();
  }

  private UUID insertSession(String state, String currency, int accepted, String expiresOffset)
      throws SQLException {
    UUID id = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_import_session (id, user_id, format_id, state, currency,"
                    + " created_at, state_changed_at, expires_at, accepted_rows)"
                    + " VALUES (?, ?, 'test-format', ?, ?, now(), now(), now() + ?::interval, ?)")) {
      insert.setObject(1, id);
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setString(3, state);
      insert.setString(4, currency);
      insert.setString(5, expiresOffset);
      insert.setInt(6, accepted);
      insert.executeUpdate();
    }
    return id;
  }

  private void insertRow(UUID session, int number, String status, String code, Long amount, boolean dated)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_import_row (id, session_id, user_id, row_number, status,"
                    + " rejection_code, transaction_date, amount_minor)"
                    + " VALUES (?, ?, ?, ?, ?, ?, ?, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, session);
      insert.setObject(3, UUID.fromString(PrudentTest.ALICE));
      insert.setInt(4, number);
      insert.setString(5, status);
      insert.setString(6, code);
      insert.setObject(7, dated ? LocalDate.of(2026, 11, 1) : null);
      insert.setObject(8, amount);
      insert.executeUpdate();
    }
  }

  private static void assertRefused(String constraint, SQLException refused) {
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected " + constraint + " but the database said: " + refused.getMessage());
  }

  @Test
  void aWellFormedSessionAndItsRowsAreAccepted() throws SQLException {
    UUID session = insertSession("PARSED", "PLN", 0, "1 hour");
    insertRow(session, 1, "ACCEPTED", null, -12_34L, true);
    insertRow(session, 2, "REJECTED", "amount.invalid", null, false);
    insertRow(session, 3, "DUPLICATE", null, 5L, true);
  }

  @ParameterizedTest
  @CsvSource({
    "prudent_import_session_state_known, DONE, PLN, 0, 1 hour",
    "prudent_import_session_state_known, parsed, PLN, 0, 1 hour",
    "prudent_import_session_currency_upper, PARSED, pln, 0, 1 hour",
    "prudent_import_session_counts_not_negative, PARSED, PLN, -1, 1 hour",
    "prudent_import_session_expiry_after_creation, PARSED, PLN, 0, -1 hour",
  })
  void sessionConstraintsRefuseWhatTheyName(
      String constraint, String state, String currency, int accepted, String expiry) {
    SQLException refused =
        assertThrows(SQLException.class, () -> insertSession(state, currency, accepted, expiry));
    assertRefused(constraint, refused);
  }

  @Test
  void rowConstraintsRefuseWhatTheyName() throws SQLException {
    UUID session = insertSession("PARSED", "PLN", 0, "1 hour");
    insertRow(session, 1, "ACCEPTED", null, 100L, true);

    assertRefused(
        "prudent_import_row_unique_number",
        assertThrows(SQLException.class, () -> insertRow(session, 1, "ACCEPTED", null, 100L, true)));
    assertRefused(
        "prudent_import_row_number_positive",
        assertThrows(SQLException.class, () -> insertRow(session, 0, "ACCEPTED", null, 100L, true)));
    assertRefused(
        "prudent_import_row_status_known",
        assertThrows(SQLException.class, () -> insertRow(session, 2, "PENDING", null, 100L, true)));
    // A row that may be written must say when and how much.
    assertRefused(
        "prudent_import_row_writable_is_complete",
        assertThrows(SQLException.class, () -> insertRow(session, 3, "ACCEPTED", null, null, true)));
    assertRefused(
        "prudent_import_row_writable_is_complete",
        assertThrows(SQLException.class, () -> insertRow(session, 4, "DUPLICATE", null, 100L, false)));
    // A rejection code exactly when rejected.
    assertRefused(
        "prudent_import_row_rejection_code_iff_rejected",
        assertThrows(SQLException.class, () -> insertRow(session, 5, "REJECTED", null, null, false)));
    assertRefused(
        "prudent_import_row_rejection_code_iff_rejected",
        assertThrows(SQLException.class, () -> insertRow(session, 6, "ACCEPTED", "a.b", 100L, true)));
    assertRefused(
        "prudent_import_row_amount_not_zero",
        assertThrows(SQLException.class, () -> insertRow(session, 7, "ACCEPTED", null, 0L, true)));
  }

  @Test
  void aRowCannotPointAtASessionThatDoesNotExist() {
    assertTrue(
        assertThrows(
                SQLException.class, () -> insertRow(UUID.randomUUID(), 1, "ACCEPTED", null, 1L, true))
            .getMessage()
            .contains("prudent_import_row_session_id_fkey"));
  }

  @Test
  void aStatementIdentityIsAnAbsentOrWellFormedDigest() throws SQLException {
    insertSessionWithIdentity(null);
    insertSessionWithIdentity("a".repeat(64));
    for (String bad : new String[] {"A".repeat(64), "a".repeat(63), "g".repeat(64)}) {
      assertRefused(
          "prudent_import_session_identity_is_digest",
          assertThrows(SQLException.class, () -> insertSessionWithIdentity(bad)));
    }
  }

  private void insertSessionWithIdentity(String identity) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_import_session (id, user_id, format_id, currency, created_at,"
                    + " state_changed_at, expires_at, statement_identity)"
                    + " VALUES (?, ?, 'test-format', 'PLN', now(), now(), now() + interval '1 hour',"
                    + " ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setString(3, identity);
      insert.executeUpdate();
    }
  }
}
