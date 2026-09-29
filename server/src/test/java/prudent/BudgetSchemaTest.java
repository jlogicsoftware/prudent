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
 * Migration coverage for {@code prudent_budget} (V20261002090000, ADR-043): the slot is unique and
 * the structural invariants of a budget hold in the database itself, against a writer that skips
 * the resource.
 *
 * <p>Plain SQL through the owner connection on purpose — the point is what the schema refuses when
 * nothing in Java has validated first. Each refusal is matched by CONSTRAINT NAME, so a test cannot
 * pass on an unrelated error such as a missing foreign-key target.
 */
@QuarkusTest
class BudgetSchemaTest {

  @Inject DataSource dataSource;

  private UUID categoryId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
  }

  private void insert(String user, UUID category, String month, String currency, long amount)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_budget (id, user_id, category_id, budget_month, currency,"
                    + " amount_minor) VALUES (?, ?, ?, ?::date, ?, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(user));
      insert.setObject(3, category);
      insert.setString(4, month);
      insert.setString(5, currency);
      insert.setLong(6, amount);
      insert.executeUpdate();
    }
  }

  private int rows() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet rows = statement.executeQuery("SELECT count(*) FROM prudent_budget")) {
      assertTrue(rows.next());
      return rows.getInt(1);
    }
  }

  @Test
  void aWellFormedRowIsAcceptedAndTheNeighbouringSlotsAreDistinct() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", 500_00L);
    // Each of these differs from the first in exactly one part of the slot.
    insert(PrudentTest.ALICE, categoryId, "2026-11-01", "PLN", 500_00L);
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "EUR", 500_00L);
    insert(PrudentTest.ALICE, PrudentTest.seedCategory(PrudentTest.ALICE, "Rent"), "2026-10-01",
        "PLN", 500_00L);
    insert(PrudentTest.BOB, categoryId, "2026-10-01", "PLN", 500_00L);

    assertEquals(5, rows());
  }

  @Test
  void aSlotCannotHoldTwoAmounts() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", 500_00L);

    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", 700_00L));

    assertTrue(
        refused.getMessage().contains("prudent_budget_unique_slot"),
        "expected the unique-slot constraint, got: " + refused.getMessage());
    assertEquals(1, rows());
  }

  @ParameterizedTest(name = "{0}")
  @CsvSource({
    "prudent_budget_amount_positive, 2026-10-01, PLN, 0",
    "prudent_budget_amount_positive, 2026-10-01, PLN, -1",
    "prudent_budget_month_is_first,  2026-10-02, PLN, 100",
    "prudent_budget_month_is_first,  2026-10-31, PLN, 100",
    "prudent_budget_currency_upper,  2026-10-01, pln, 100",
  })
  void aStructurallyImpossibleRowIsRefusedByTheSchema(
      String constraint, String month, String currency, long amount) {
    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> insert(PrudentTest.ALICE, categoryId, month, currency, amount));
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected a violation of " + constraint + ", got: " + refused.getMessage());
  }

  @Test
  void aBudgetCannotOutliveItsCategory() throws SQLException {
    insert(PrudentTest.ALICE, categoryId, "2026-10-01", "PLN", 500_00L);

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
        refused.getMessage().contains("prudent_budget"),
        "expected the budget foreign key, got: " + refused.getMessage());
  }
}
