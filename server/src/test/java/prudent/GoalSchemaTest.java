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
 * Migration coverage for {@code prudent_goal} (V20261005090000, ADR-049): the structural
 * invariants of a goal hold in the database itself, against a writer that skips the resource.
 *
 * <p>Plain SQL through the owner connection on purpose — the point is what the schema refuses when
 * nothing in Java has validated first. Each refusal is matched by CONSTRAINT NAME, so a test cannot
 * pass on an unrelated error.
 */
@QuarkusTest
class GoalSchemaTest {

  @Inject DataSource dataSource;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
  }

  private void insert(String name, String currency, long target, String status, String date)
      throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_goal (id, user_id, name, currency, target_amount_minor,"
                    + " target_date, status, created_at, status_changed_at)"
                    + " VALUES (?, ?, ?, ?, ?, ?::date, ?, now(), now())")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setString(3, name);
      insert.setString(4, currency);
      insert.setLong(5, target);
      insert.setString(6, date);
      insert.setString(7, status);
      insert.executeUpdate();
    }
  }

  private int rows() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet rows = statement.executeQuery("SELECT count(*) FROM prudent_goal")) {
      assertTrue(rows.next());
      return rows.getInt(1);
    }
  }

  @Test
  void aWellFormedRowIsAcceptedWithAndWithoutADate() throws SQLException {
    insert("Holiday", "PLN", 5_000_00L, "ACTIVE", "2027-06-01");
    insert("Rainy day", "EUR", 1_000_00L, "COMPLETED", null);
    insert("Old plan", "PLN", 1L, "ARCHIVED", null);

    assertEquals(3, rows());
  }

  @Test
  void aGoalWithoutAStatusStartsActive() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      statement.executeUpdate(
          "INSERT INTO prudent_goal (id, user_id, name, currency, target_amount_minor, created_at,"
              + " status_changed_at) VALUES ('" + UUID.randomUUID() + "', '" + PrudentTest.ALICE
              + "', 'Car', 'PLN', 100, now(), now())");
      try (ResultSet row = statement.executeQuery("SELECT status FROM prudent_goal")) {
        assertTrue(row.next());
        assertEquals("ACTIVE", row.getString(1));
      }
    }
  }

  @ParameterizedTest(name = "{0}")
  @CsvSource({
    "prudent_goal_target_positive, Holiday, PLN, 0, ACTIVE",
    "prudent_goal_target_positive, Holiday, PLN, -1, ACTIVE",
    "prudent_goal_currency_upper,  Holiday, pln, 100, ACTIVE",
    "prudent_goal_status_known,    Holiday, PLN, 100, DONE",
    "prudent_goal_status_known,    Holiday, PLN, 100, active",
  })
  void aStructurallyImpossibleRowIsRefusedByTheSchema(
      String constraint, String name, String currency, long target, String status) {
    SQLException refused =
        assertThrows(SQLException.class, () -> insert(name, currency, target, status, null));
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected a violation of " + constraint + ", got: " + refused.getMessage());
  }

  @Test
  void aBlankNameIsRefusedByTheSchema() {
    for (String blank : new String[] {"", "   "}) {
      SQLException refused =
          assertThrows(
              SQLException.class, () -> insert(blank, "PLN", 100, "ACTIVE", null));
      assertTrue(
          refused.getMessage().contains("prudent_goal_name_not_blank"),
          "expected the name constraint, got: " + refused.getMessage());
    }
  }
}
