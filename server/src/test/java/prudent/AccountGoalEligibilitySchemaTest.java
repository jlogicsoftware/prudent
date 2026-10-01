package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for {@code prudent_account.eligible_for_goals} (V20261007090000, ADR-051):
 * the flag exists, is never null, and is off for an account nobody has marked.
 *
 * <p>Plain SQL through the owner connection on purpose — what the schema does when nothing in Java
 * has set the column.
 */
@QuarkusTest
class AccountGoalEligibilitySchemaTest {

  @Inject DataSource dataSource;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  private boolean eligible(Statement statement, UUID id) throws SQLException {
    try (ResultSet row =
        statement.executeQuery(
            "SELECT eligible_for_goals FROM prudent_account WHERE id = '" + id + "'")) {
      assertTrue(row.next());
      return row.getBoolean(1);
    }
  }

  @Test
  void anAccountInsertedWithoutTheColumnIsNotEligible() throws SQLException {
    UUID id = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      statement.executeUpdate(
          "INSERT INTO prudent_account (id, user_id, name, kind) VALUES ('"
              + id + "', '" + PrudentTest.ALICE + "', 'Plain', 'CASH')");

      assertFalse(eligible(statement, id), "no account is drawn on until the user says so");
    }
  }

  @Test
  void theColumnCannotBeNull() throws SQLException {
    UUID id = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      SQLException refused =
          assertThrows(
              SQLException.class,
              () ->
                  statement.executeUpdate(
                      "INSERT INTO prudent_account (id, user_id, name, kind, eligible_for_goals)"
                          + " VALUES ('" + id + "', '" + PrudentTest.ALICE
                          + "', 'Null', 'CASH', NULL)"));
      assertTrue(
          refused.getMessage().contains("eligible_for_goals"),
          "expected a violation of the column, got: " + refused.getMessage());
    }
  }

  @Test
  void aSeededEligibleAccountReadsBackEligible() throws SQLException {
    UUID id = PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 1_00L, "PLN");
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      assertEquals(true, eligible(statement, id));
    }
  }
}
