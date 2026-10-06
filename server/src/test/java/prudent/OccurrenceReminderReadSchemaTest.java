package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for {@code prudent_plan_occurrence.reminder_read_at} (V20261009090000,
 * ADR-055): the column exists, a row nobody has read is unread (NULL, never a default timestamp),
 * the value round-trips, and an occurrence's deletion takes its read state with it because it is the
 * same row.
 *
 * <p>Plain SQL through the owner connection on purpose — what the schema does when nothing in Java
 * has set the column.
 */
@QuarkusTest
class OccurrenceReminderReadSchemaTest {

  @Inject DataSource dataSource;

  private UUID occurrenceId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    UUID planId = PrudentTest.seedPlan(PrudentTest.ALICE, accountId, categoryId, -100L, "PLN");
    occurrenceId = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, LocalDate.of(2026, 10, 1));
  }

  @Test
  void anOccurrenceNobodyHasReadIsUnreadAndNullable() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet column =
            statement.executeQuery(
                "SELECT is_nullable, data_type FROM information_schema.columns"
                    + " WHERE table_name = 'prudent_plan_occurrence'"
                    + " AND column_name = 'reminder_read_at'")) {
      assertTrue(column.next(), "the column exists");
      assertEquals("YES", column.getString("is_nullable"), "NULL is what unread is");
      assertEquals("timestamp with time zone", column.getString("data_type"));
    }
    assertNull(readAt());
  }

  @Test
  void aReadTimeRoundTripsAndCanBeClearedAgain() throws SQLException {
    Instant when = Instant.parse("2026-10-15T10:00:00Z");
    set(Timestamp.from(when));
    assertEquals(when, readAt());

    set(null);
    assertNull(readAt());
  }

  @Test
  void deletingTheOccurrenceDeletesItsReadStateBecauseItIsTheSameRow() throws SQLException {
    set(Timestamp.from(Instant.parse("2026-10-15T10:00:00Z")));
    try (Connection owner = dataSource.getConnection();
        PreparedStatement delete =
            owner.prepareStatement("DELETE FROM prudent_plan_occurrence WHERE id = ?")) {
      delete.setObject(1, occurrenceId);
      assertEquals(1, delete.executeUpdate());
    }
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet row =
            statement.executeQuery(
                "SELECT count(*) FROM prudent_plan_occurrence WHERE id = '" + occurrenceId + "'")) {
      assertTrue(row.next());
      assertEquals(0, row.getInt(1));
    }
  }

  private Instant readAt() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet row =
            statement.executeQuery(
                "SELECT reminder_read_at FROM prudent_plan_occurrence WHERE id = '"
                    + occurrenceId
                    + "'")) {
      assertTrue(row.next());
      Timestamp value = row.getTimestamp("reminder_read_at");
      return value == null ? null : value.toInstant();
    }
  }

  private void set(Timestamp value) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement update =
            owner.prepareStatement(
                "UPDATE prudent_plan_occurrence SET reminder_read_at = ? WHERE id = ?")) {
      update.setTimestamp(1, value);
      update.setObject(2, occurrenceId);
      update.executeUpdate();
    }
  }
}
