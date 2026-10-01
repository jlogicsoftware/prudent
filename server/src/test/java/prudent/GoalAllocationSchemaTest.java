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
 * Migration coverage for {@code prudent_goal_allocation} (V20261006090000, ADR-050): the structural
 * invariants of an envelope entry hold in the database itself, against a writer that skips the
 * resource — including that the history cannot be rewritten.
 *
 * <p>Plain SQL through the owner connection on purpose — the point is what the schema refuses when
 * nothing in Java has validated first. Each refusal is matched by CONSTRAINT NAME, so a test cannot
 * pass on an unrelated error.
 */
@QuarkusTest
class GoalAllocationSchemaTest {

  @Inject DataSource dataSource;

  private UUID pln;
  private UUID plnToo;
  private UUID eur;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    pln = PrudentTest.seedGoal(PrudentTest.ALICE, "Holiday", "PLN", 100_00L);
    plnToo = PrudentTest.seedGoal(PrudentTest.ALICE, "Car", "PLN", 100_00L);
    eur = PrudentTest.seedGoal(PrudentTest.ALICE, "Rainy day", "EUR", 100_00L);
  }

  private UUID insert(String kind, UUID source, UUID target, String currency, long amount, String note)
      throws SQLException {
    UUID id = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_goal_allocation (id, user_id, kind, source_goal_id,"
                    + " target_goal_id, currency, amount_minor, note, created_at, created_by)"
                    + " VALUES (?, ?, ?, ?, ?, ?, ?, ?, now(), ?)")) {
      insert.setObject(1, id);
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.setString(3, kind);
      insert.setObject(4, source);
      insert.setObject(5, target);
      insert.setString(6, currency);
      insert.setLong(7, amount);
      insert.setString(8, note);
      insert.setObject(9, UUID.fromString(PrudentTest.ALICE));
      insert.executeUpdate();
    }
    return id;
  }

  private int rows() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement();
        ResultSet rows =
            statement.executeQuery("SELECT count(*) FROM prudent_goal_allocation")) {
      assertTrue(rows.next());
      return rows.getInt(1);
    }
  }

  private void assertRefused(String constraint, SQLException refused) {
    assertTrue(
        refused.getMessage().contains(constraint),
        "expected a violation of " + constraint + ", got: " + refused.getMessage());
  }

  @Test
  void aWellFormedEntryOfEveryKindIsAccepted() throws SQLException {
    insert("ALLOCATE", null, pln, "PLN", 100, "");
    insert("WITHDRAW", pln, null, "PLN", 50, "released");
    insert("MOVE", pln, plnToo, "PLN", 25, "");

    assertEquals(3, rows());
  }

  @Test
  void aNoteDefaultsToEmpty() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      statement.executeUpdate(
          "INSERT INTO prudent_goal_allocation (id, user_id, kind, target_goal_id, currency,"
              + " amount_minor, created_at, created_by) VALUES ('" + UUID.randomUUID() + "', '"
              + PrudentTest.ALICE + "', 'ALLOCATE', '" + pln + "', 'PLN', 1, now(), '"
              + PrudentTest.ALICE + "')");
      try (ResultSet row = statement.executeQuery("SELECT note FROM prudent_goal_allocation")) {
        assertTrue(row.next());
        assertEquals("", row.getString(1));
      }
    }
  }

  @ParameterizedTest(name = "{0}")
  @CsvSource({
    "prudent_goal_allocation_amount_positive, 0",
    "prudent_goal_allocation_amount_positive, -1",
  })
  void anAmountThatIsNotPositiveIsRefused(String constraint, long amount) {
    assertRefused(
        constraint,
        assertThrows(SQLException.class, () -> insert("ALLOCATE", null, pln, "PLN", amount, "")));
  }

  @Test
  void anUnknownKindIsRefused() {
    assertRefused(
        "prudent_goal_allocation_kind_known",
        assertThrows(SQLException.class, () -> insert("REFUND", null, pln, "PLN", 1, "")));
    assertRefused(
        "prudent_goal_allocation_kind_known",
        assertThrows(SQLException.class, () -> insert("allocate", null, pln, "PLN", 1, "")));
  }

  @Test
  void aKindThatNamesTheWrongGoalsIsRefused() {
    String shape = "prudent_goal_allocation_shape";
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("ALLOCATE", null, null, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("ALLOCATE", pln, pln, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("ALLOCATE", pln, null, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("WITHDRAW", null, pln, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("WITHDRAW", pln, plnToo, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("MOVE", pln, null, "PLN", 1, "")));
    assertRefused(shape, assertThrows(SQLException.class, () -> insert("MOVE", null, pln, "PLN", 1, "")));
  }

  @Test
  void aMoveToTheSameGoalIsRefused() {
    assertRefused(
        "prudent_goal_allocation_shape",
        assertThrows(SQLException.class, () -> insert("MOVE", pln, pln, "PLN", 1, "")));
  }

  @Test
  void aCurrencyThatIsNotTheGoalsIsRefusedOnEitherSide() {
    assertRefused(
        "prudent_goal_allocation_target_fk",
        assertThrows(SQLException.class, () -> insert("ALLOCATE", null, pln, "EUR", 1, "")));
    assertRefused(
        "prudent_goal_allocation_source_fk",
        assertThrows(SQLException.class, () -> insert("WITHDRAW", pln, null, "EUR", 1, "")));
    // A move between currencies has no currency that suits both goals.
    assertThrows(SQLException.class, () -> insert("MOVE", pln, eur, "PLN", 1, ""));
    assertThrows(SQLException.class, () -> insert("MOVE", pln, eur, "EUR", 1, ""));
  }

  @Test
  void aLowerCaseCurrencyIsRefused() {
    // CHECK constraints are evaluated before foreign keys, so the entry's own rule is the one named.
    assertRefused(
        "prudent_goal_allocation_currency_upper",
        assertThrows(SQLException.class, () -> insert("ALLOCATE", null, pln, "pln", 1, "")));
  }

  @Test
  void aGoalThatDoesNotExistIsRefused() {
    assertRefused(
        "prudent_goal_allocation_target_fk",
        assertThrows(
            SQLException.class, () -> insert("ALLOCATE", null, UUID.randomUUID(), "PLN", 1, "")));
  }

  @Test
  void aNoteOfFiveHundredCharactersIsAcceptedAndLongerIsRefused() throws SQLException {
    insert("ALLOCATE", null, pln, "PLN", 1, "é".repeat(500));
    assertRefused(
        "prudent_goal_allocation_note_length",
        assertThrows(SQLException.class, () -> insert("ALLOCATE", null, pln, "PLN", 1, "x".repeat(501))));
  }

  @Test
  void aGoalWithHistoryCannotBeDeleted() throws SQLException {
    insert("ALLOCATE", null, pln, "PLN", 1, "");

    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      SQLException refused =
          assertThrows(
              SQLException.class,
              () -> statement.executeUpdate("DELETE FROM prudent_goal WHERE id = '" + pln + "'"));
      assertRefused("prudent_goal_allocation_target_fk", refused);
    }
  }

  @Test
  void anEntryCanNeverBeChanged() throws SQLException {
    UUID id = insert("ALLOCATE", null, pln, "PLN", 100, "original");

    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      for (String change :
          new String[] {
            "SET amount_minor = 1", "SET note = 'rewritten'", "SET kind = 'WITHDRAW', source_goal_id = target_goal_id, target_goal_id = NULL",
            "SET created_at = now() - interval '1 day'", "SET id = gen_random_uuid()"
          }) {
        SQLException refused =
            assertThrows(
                SQLException.class,
                () ->
                    statement.executeUpdate(
                        "UPDATE prudent_goal_allocation " + change + " WHERE id = '" + id + "'"),
                change);
        assertTrue(
            refused.getMessage().contains("append-only"),
            "expected the history to refuse the change, got: " + refused.getMessage());
      }
      try (ResultSet row =
          statement.executeQuery(
              "SELECT amount_minor, note FROM prudent_goal_allocation WHERE id = '" + id + "'")) {
        assertTrue(row.next());
        assertEquals(100, row.getLong(1));
        assertEquals("original", row.getString(2));
      }
    }
  }

  @Test
  void anEntryCanBeRemovedOnlyByDeletion() throws SQLException {
    // Deletion is not blocked: the retention cascade for an anonymised user depends on it.
    UUID id = insert("ALLOCATE", null, pln, "PLN", 1, "");
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      assertEquals(
          1,
          statement.executeUpdate("DELETE FROM prudent_goal_allocation WHERE id = '" + id + "'"));
    }
    assertEquals(0, rows());
  }
}
