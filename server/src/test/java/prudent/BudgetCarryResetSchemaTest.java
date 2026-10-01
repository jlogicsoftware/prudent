package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * Migration coverage for {@code prudent_budget_carry_reset} (V20261003090000, ADR-046): at most one
 * live reset per slot, a revoked one does not count, and the structural invariants of an audit
 * entry hold in the database against a writer that skips the resource.
 *
 * <p>Each refusal is matched by constraint or index name, so a test cannot pass on an unrelated
 * error such as a missing foreign-key target.
 */
@QuarkusTest
class BudgetCarryResetSchemaTest {

  @Inject DataSource dataSource;

  private UUID categoryId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
  }

  private void insert(
      String user, UUID category, String month, String currency, String note, boolean revoked)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_budget_carry_reset (id, user_id, category_id, reset_month,"
                    + " currency, discarded_minor, note, created_at, created_by, revoked_at,"
                    + " revoked_by) VALUES (?, ?, ?, ?::date, ?, 0, ?, now(), ?,"
                    + " CASE WHEN ? THEN now() END, CASE WHEN ? THEN ?::uuid END)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(user));
      insert.setObject(3, category);
      insert.setString(4, month);
      insert.setString(5, currency);
      insert.setString(6, note);
      insert.setObject(7, UUID.fromString(user));
      insert.setBoolean(8, revoked);
      insert.setBoolean(9, revoked);
      insert.setString(10, user);
      insert.executeUpdate();
    }
  }

  private int rows() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet rows =
            statement.executeQuery("SELECT count(*) FROM prudent_budget_carry_reset")) {
      assertTrue(rows.next());
      return rows.getInt(1);
    }
  }

  @Test
  void aWellFormedRowIsAcceptedAndNeighbouringSlotsAreDistinct() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", false);
    // Each differs from the first in exactly one part of the slot.
    insert(PrudentTest.ALICE, categoryId, "2026-11-01", "PLN", "", false);
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "EUR", "", false);
    insert(
        PrudentTest.ALICE,
        PrudentTest.seedCategory(PrudentTest.ALICE, "Rent"),
        "2026-10-01",
        "PLN",
        "",
        false);
    insert(PrudentTest.BOB, categoryId, "2026-10-01", "PLN", "", false);

    assertEquals(5, rows());
  }

  @Test
  void aSlotCannotHaveTwoLiveResets() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", false);

    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", false));

    assertTrue(
        refused.getMessage().contains("prudent_budget_carry_reset_live_slot"),
        "expected the live-slot index, got: " + refused.getMessage());
    assertEquals(1, rows());
  }

  @Test
  void revokedEntriesDoNotCountTowardTheLiveLimit() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", true);
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", true);
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", false);

    assertEquals(3, rows());
  }

  @ParameterizedTest(name = "{0}")
  @CsvSource({
    "prudent_budget_carry_reset_month_is_first, 2026-10-02, PLN",
    "prudent_budget_carry_reset_month_is_first, 2026-10-31, PLN",
    "prudent_budget_carry_reset_currency_upper, 2026-10-01, pln",
  })
  void aStructurallyImpossibleRowIsRefusedByTheSchema(
      String constraint, String month, String currency) {
    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> insert(PrudentTest.ALICE, categoryId, month, currency, "", false));
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected a violation of " + constraint + ", got: " + refused.getMessage());
  }

  @Test
  void aNoteLongerThanFiveHundredCharactersIsRefused() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "x".repeat(500), false);

    SQLException refused =
        assertThrows(
            SQLException.class,
            () ->
                insert(PrudentTest.ALICE, categoryId, "2026-11-01", "PLN", "x".repeat(501), false));

    assertTrue(refused.getMessage().contains("prudent_budget_carry_reset_note_length"));
  }

  @Test
  void aRevocationNamesBothWhenAndByWhomOrNeither() {
    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> {
              try (Connection owner = dataSource.getConnection();
                  PreparedStatement insert =
                      owner.prepareStatement(
                          "INSERT INTO prudent_budget_carry_reset (id, user_id, category_id,"
                              + " reset_month, currency, discarded_minor, created_at, created_by,"
                              + " revoked_at) VALUES (?, ?, ?, '2026-10-01', 'PLN', 0, now(), ?,"
                              + " now())")) {
                insert.setObject(1, UUID.randomUUID());
                insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
                insert.setObject(3, categoryId);
                insert.setObject(4, UUID.fromString(PrudentTest.ALICE));
                insert.executeUpdate();
              }
            });

    assertTrue(refused.getMessage().contains("prudent_budget_carry_reset_revocation_whole"));
  }

  @Test
  void anEntryCannotOutliveItsCategory() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", "", false);

    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> {
              try (Connection owner = dataSource.getConnection();
                  PreparedStatement delete =
                      owner.prepareStatement("DELETE FROM prudent_category WHERE id = ?")) {
                delete.setObject(1, categoryId);
                delete.executeUpdate();
              }
            });
    assertTrue(
        refused.getMessage().contains("prudent_budget_carry_reset"),
        "expected the reset foreign key, got: " + refused.getMessage());
  }
}
