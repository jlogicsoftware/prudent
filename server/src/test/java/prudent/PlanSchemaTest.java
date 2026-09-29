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
import java.sql.Types;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * Migration coverage for {@code prudent_plan} (V20260928090000, ADR-037): the structural invariants
 * of a recurrence rule hold in the database itself, against a writer that skips the resource.
 *
 * <p>Plain SQL through the owner connection on purpose — the point is what the schema refuses when
 * nothing in Java has validated first. Each refusal is matched by CONSTRAINT NAME, so a test cannot
 * pass on an unrelated error such as a missing foreign-key target.
 */
@QuarkusTest
class PlanSchemaTest {

  @Inject DataSource dataSource;

  private UUID accountId;
  private UUID categoryId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
  }

  private void insert(
      String frequency, int interval, String start, String until, Integer count)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_plan (id, user_id, title, amount_minor, currency, account_id,"
                    + " category_id, frequency, recurrence_interval, start_date, time_zone,"
                    + " until_date, occurrence_count)"
                    + " VALUES (?, ?, 'Rent', -100, 'PLN', ?, ?, ?, ?, ?::date, 'Europe/Warsaw',"
                    + " ?::date, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setObject(3, accountId);
      insert.setObject(4, categoryId);
      insert.setString(5, frequency);
      insert.setInt(6, interval);
      insert.setString(7, start);
      insert.setString(8, until);
      insert.setObject(9, count, Types.INTEGER);
      insert.executeUpdate();
    }
  }

  @Test
  void aWellFormedRowOfEachShapeIsAccepted() throws SQLException {
    insert("ONCE", 1, "2026-10-01", null, null);
    insert("MONTHLY", 3, "2026-10-01", "2027-10-01", null);
    insert("WEEKLY", 2, "2026-10-01", null, 10);
    insert("DAILY", 1, "2026-10-01", "2026-10-01", null);
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet rows = statement.executeQuery("SELECT count(*) FROM prudent_plan")) {
      assertTrue(rows.next());
      assertEquals(4, rows.getInt(1));
    }
  }

  @ParameterizedTest(name = "{0}")
  @CsvSource(
      nullValues = "null",
      value = {
        "prudent_plan_interval_positive,       DAILY,   0,    2026-10-01, null,       null",
        "prudent_plan_interval_positive,       DAILY,   1001, 2026-10-01, null,       null",
        "prudent_plan_count_positive,          DAILY,   1,    2026-10-01, null,       0",
        "prudent_plan_single_end,              DAILY,   1,    2026-10-01, 2026-12-01, 5",
        "prudent_plan_until_not_before_start,  DAILY,   1,    2026-10-01, 2026-09-30, null",
        "prudent_plan_once_is_single,          ONCE,    2,    2026-10-01, null,       null",
        "prudent_plan_once_is_single,          ONCE,    1,    2026-10-01, 2026-10-02, null",
        "prudent_plan_once_is_single,          ONCE,    1,    2026-10-01, null,       1",
      })
  void aStructurallyImpossibleRuleIsRefusedByTheSchema(
      String constraint, String frequency, int interval, String start, String until, Integer count) {
    SQLException refused =
        assertThrows(SQLException.class, () -> insert(frequency, interval, start, until, count));
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected a violation of " + constraint + ", got: " + refused.getMessage());
  }
}
