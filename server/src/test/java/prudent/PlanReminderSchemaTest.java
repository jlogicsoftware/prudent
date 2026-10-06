package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Migration coverage for the reminder columns on {@code prudent_plan} (V20261008090000, ADR-054):
 * they exist, are never null, are off for a plan nobody asked a reminder for, and the lead time is
 * structurally bounded.
 *
 * <p>Plain SQL through the owner connection on purpose — what the schema does when nothing in Java
 * has set the columns. The supported lead times are deliberately NOT a constraint; they are
 * validated by {@code ReminderSetting}, and a test here would pin the wrong layer.
 */
@QuarkusTest
class PlanReminderSchemaTest {

  @Inject DataSource dataSource;

  private UUID planId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    planId = PrudentTest.seedPlan(PrudentTest.ALICE, accountId, categoryId, -100L, "PLN");
  }

  @Test
  void aPlanWithNoReminderChosenIsOffWithAOneDayLeadTime() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet row =
            statement.executeQuery(
                "SELECT reminder_enabled, reminder_lead_days FROM prudent_plan WHERE id = '"
                    + planId
                    + "'")) {
      assertTrue(row.next());
      assertFalse(row.getBoolean("reminder_enabled"));
      assertEquals(1, row.getInt("reminder_lead_days"));
    }
  }

  @Test
  void theColumnsCannotBeNull() {
    for (String column : new String[] {"reminder_enabled", "reminder_lead_days"}) {
      SQLException refused = assertThrows(SQLException.class, () -> setNull(column));
      assertTrue(
          refused.getMessage().contains("null value in column \"" + column + "\""),
          "expected a not-null violation on " + column + ", got: " + refused.getMessage());
    }
  }

  @ParameterizedTest
  @ValueSource(ints = {0, 1, 7, 30, 365})
  void aLeadTimeWithinTheStructuralBoundsIsAccepted(int days) throws SQLException {
    setLeadDays(days);
  }

  @ParameterizedTest
  @ValueSource(ints = {-1, 366, Integer.MAX_VALUE})
  void aLeadTimeOutsideTheStructuralBoundsIsRefused(int days) {
    SQLException refused = assertThrows(SQLException.class, () -> setLeadDays(days));
    assertTrue(
        refused.getMessage().contains("prudent_plan_reminder_lead_days_range"),
        "expected the lead-days range constraint, got: " + refused.getMessage());
  }

  private void setLeadDays(int days) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement update =
            owner.prepareStatement("UPDATE prudent_plan SET reminder_lead_days = ? WHERE id = ?")) {
      update.setInt(1, days);
      update.setObject(2, planId);
      update.executeUpdate();
    }
  }

  private void setNull(String column) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement update =
            owner.prepareStatement("UPDATE prudent_plan SET " + column + " = NULL WHERE id = ?")) {
      update.setObject(1, planId);
      update.executeUpdate();
    }
  }
}
