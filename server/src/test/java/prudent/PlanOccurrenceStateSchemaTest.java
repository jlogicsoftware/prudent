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
import java.time.LocalDate;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for {@code prudent_plan_occurrence.state} (V20260930090000, ADR-039), through
 * plain SQL on the owner connection so it reads what the schema does with no Java in between.
 */
@QuarkusTest
class PlanOccurrenceStateSchemaTest {

  @Inject DataSource dataSource;

  private UUID planId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    UUID category = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    planId = PrudentTest.seedPlan(PrudentTest.ALICE, account, category, -1L, "PLN");
  }

  private void insert(String state) throws SQLException {
    String sql =
        state == null
            ? "INSERT INTO prudent_plan_occurrence (id, user_id, plan_id, occurrence_date)"
                + " VALUES (?, ?, ?, ?)"
            : "INSERT INTO prudent_plan_occurrence (id, user_id, plan_id, occurrence_date, state)"
                + " VALUES (?, ?, ?, ?, ?)";
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert = owner.prepareStatement(sql)) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setObject(3, planId);
      insert.setObject(4, LocalDate.of(2026, 10, 1));
      if (state != null) {
        insert.setString(5, state);
      }
      insert.executeUpdate();
    }
  }

  private String storedState() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement select =
            owner.prepareStatement("SELECT state FROM prudent_plan_occurrence");
        ResultSet rows = select.executeQuery()) {
      assertTrue(rows.next());
      return rows.getString(1);
    }
  }

  @Test
  void anOccurrenceWrittenWithNoStateIsPlanned() throws Exception {
    // Every row generated before the column existed took this path, and the generator's insert
    // still names no state.
    insert(null);

    assertEquals("PLANNED", storedState());
  }

  @Test
  void aStateIsStoredAsItWasWritten() throws Exception {
    insert("SKIPPED");

    assertEquals("SKIPPED", storedState());
  }

  @Test
  void theColumnCannotBeNull() {
    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> {
              try (Connection owner = dataSource.getConnection();
                  PreparedStatement insert =
                      owner.prepareStatement(
                          "INSERT INTO prudent_plan_occurrence"
                              + " (id, user_id, plan_id, occurrence_date, state)"
                              + " VALUES (?, ?, ?, '2026-10-01', NULL)")) {
                insert.setObject(1, UUID.randomUUID());
                insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
                insert.setObject(3, planId);
                insert.executeUpdate();
              }
            });
    assertTrue(refused.getMessage().contains("state"), refused.getMessage());
  }
}
