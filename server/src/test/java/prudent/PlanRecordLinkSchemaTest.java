package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
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
import prudent.record.RecordEntity;

/**
 * Migration coverage for {@code prudent_record.plan_id} / {@code plan_occurrence_id}
 * (V20261001090000, ADR-040), through plain SQL on the owner connection so it reads what the schema
 * itself refuses, with no resource in between. The resource serialises confirmations with a row
 * lock; these are the guarantees that hold for a writer that does not go through it.
 */
@QuarkusTest
class PlanRecordLinkSchemaTest {

  @Inject DataSource dataSource;

  private UUID account;
  private UUID category;
  private UUID planId;
  private UUID occurrenceId;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    category = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    planId = PrudentTest.seedPlan(PrudentTest.ALICE, account, category, -1L, "PLN");
    occurrenceId = PrudentTest.seedOccurrence(PrudentTest.ALICE, planId, LocalDate.of(2026, 10, 1));
  }

  private void insertRecord(UUID linkedPlan, UUID linkedOccurrence) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_record (id, user_id, title, amount_minor, currency,"
                    + " record_date, category_id, account_id, plan_id, plan_occurrence_id)"
                    + " VALUES (?, ?, 'Rent', -1, 'PLN', '2026-10-01', ?, ?, ?, ?)")) {
      insert.setObject(1, UUID.randomUUID());
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setObject(3, category);
      insert.setObject(4, account);
      insert.setObject(5, linkedPlan);
      insert.setObject(6, linkedOccurrence);
      insert.executeUpdate();
    }
  }

  private void execute(String sql) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement statement = owner.prepareStatement(sql)) {
      statement.setObject(1, occurrenceId);
      statement.executeUpdate();
    }
  }

  @Test
  void anOccurrenceCannotBeConfirmedIntoTwoRecords() throws Exception {
    insertRecord(planId, occurrenceId);

    SQLException refused =
        assertThrows(SQLException.class, () -> insertRecord(planId, occurrenceId));

    assertTrue(
        refused.getMessage().contains("prudent_record_plan_occurrence_unique"),
        refused.getMessage());
  }

  @Test
  void recordsWithNoPlanLinkDoNotCollideWithEachOther() throws Exception {
    // The index is partial: the great majority of records have no plan, and NULLs must coexist.
    insertRecord(null, null);
    insertRecord(null, null);

    assertEquals(2, QuarkusTransaction.requiringNew().call(() -> RecordEntity.count()));
  }

  @Test
  void theTwoLinkColumnsTravelTogether() {
    for (UUID[] half : new UUID[][] {{planId, null}, {null, occurrenceId}}) {
      SQLException refused = assertThrows(SQLException.class, () -> insertRecord(half[0], half[1]));
      assertTrue(
          refused.getMessage().contains("prudent_record_plan_link_paired"), refused.getMessage());
    }
  }

  @Test
  void aLinkedOccurrenceCannotBeDeletedFromUnderItsRecord() throws Exception {
    insertRecord(planId, occurrenceId);

    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> execute("DELETE FROM prudent_plan_occurrence WHERE id = ?"));

    // No cascade: a ledger row never vanishes because something it points at was removed.
    assertTrue(refused.getMessage().contains("violates foreign key"), refused.getMessage());
  }

  @Test
  void aRecordCannotPointAtAPlanThatDoesNotExist() {
    assertThrows(SQLException.class, () -> insertRecord(UUID.randomUUID(), UUID.randomUUID()));
  }
}
