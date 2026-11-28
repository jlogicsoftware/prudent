package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import javax.sql.DataSource;
import org.eclipse.microprofile.config.ConfigProvider;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The backfill of {@code V20261128075749__prudent_goal_allocation_order} (ADR-139): entries written
 * before the history had a recording order are numbered so that it reads as it read before, and
 * entries written afterwards come above them.
 *
 * <p>Every other test runs against a schema that was migrated while empty, where a backfill does
 * nothing. So this one builds a database of its own in the test server, stops Flyway at the version
 * before, writes rows, and then lets it finish.
 */
@QuarkusTest
class GoalAllocationOrderMigrationTest {

  private static final String DATABASE = "prudent_allocation_order_backfill";

  private static final String BEFORE = "20261127185652";

  private static final String USER = PrudentTest.ALICE;

  private static final String GOAL = "00000000-0000-4000-8000-00000000000a";

  @Inject DataSource dataSource;

  private String url;
  private String username;
  private String password;

  @BeforeEach
  void createAnEmptyDatabase() throws SQLException {
    username = ConfigProvider.getConfig().getValue("quarkus.datasource.username", String.class);
    password = ConfigProvider.getConfig().getValue("quarkus.datasource.password", String.class);
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      String shared = owner.getMetaData().getURL();
      url = shared.replaceFirst("(//[^/]+/)[^?]+", "$1" + DATABASE);
      statement.execute("DROP DATABASE IF EXISTS " + DATABASE + " WITH (FORCE)");
      statement.execute("CREATE DATABASE " + DATABASE);
    }
  }

  @AfterEach
  void dropIt() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      statement.execute("DROP DATABASE IF EXISTS " + DATABASE + " WITH (FORCE)");
    }
  }

  @Test
  void existingEntriesKeepTheOrderTheHistoryShowedAndNewOnesComeAfterThem() throws SQLException {
    migrate(BEFORE);
    try (Connection owner = connect();
        Statement statement = owner.createStatement()) {
      statement.executeUpdate(
          "INSERT INTO prudent_goal (id, user_id, name, currency, target_amount_minor, status,"
              + " created_at, status_changed_at) VALUES ('" + GOAL + "', '" + USER
              + "', 'Holiday', 'PLN', 100, 'ACTIVE', now(), now())");
      // Inserted in neither time nor id order, so the numbering cannot come from where the rows lie.
      insert(statement, 3, "2026-01-02T00:00:00Z");
      insert(statement, 5, "2026-01-01T00:00:00Z");
      insert(statement, 1, "2026-01-02T00:00:00Z");
      insert(statement, 4, "2026-01-03T00:00:00Z");
      insert(statement, 2, "2026-01-02T00:00:00Z");
    }

    migrate("latest");

    // What `created_at DESC, id` answered before the migration: the three of one instant by id.
    assertEquals(List.of(id(4), id(1), id(2), id(3), id(5)), newestFirst());

    try (Connection owner = connect();
        Statement statement = owner.createStatement()) {
      // Stamped earlier than everything: the number, not the time, puts it first.
      insert(statement, 6, "2020-01-01T00:00:00Z");
    }

    assertEquals(List.of(id(6), id(4), id(1), id(2), id(3), id(5)), newestFirst());
    assertEquals(List.of(6L, 5L, 4L, 3L, 2L, 1L), numbers(), "no gap and no number reused");
    assertRewritingIsStillRefused();
  }

  private void migrate(String target) {
    Flyway.configure(Thread.currentThread().getContextClassLoader())
        .dataSource(url, username, password)
        .locations("db/migration")
        .target(target)
        .load()
        .migrate();
  }

  private Connection connect() throws SQLException {
    return DriverManager.getConnection(url, username, password);
  }

  private static UUID id(int n) {
    return new UUID(0, n);
  }

  private static void insert(Statement statement, int n, String createdAt) throws SQLException {
    statement.executeUpdate(
        "INSERT INTO prudent_goal_allocation (id, user_id, kind, target_goal_id, currency,"
            + " amount_minor, created_at, created_by) VALUES ('" + id(n) + "', '" + USER
            + "', 'ALLOCATE', '" + GOAL + "', 'PLN', 1, '" + createdAt + "', '" + USER + "')");
  }

  private List<UUID> newestFirst() throws SQLException {
    List<UUID> ids = new ArrayList<>();
    try (Connection owner = connect();
        Statement statement = owner.createStatement();
        ResultSet rows =
            statement.executeQuery(
                "SELECT id FROM prudent_goal_allocation ORDER BY recorded_seq DESC")) {
      while (rows.next()) {
        ids.add(rows.getObject(1, UUID.class));
      }
    }
    return ids;
  }

  private List<Long> numbers() throws SQLException {
    List<Long> numbers = new ArrayList<>();
    try (Connection owner = connect();
        Statement statement = owner.createStatement();
        ResultSet rows =
            statement.executeQuery(
                "SELECT recorded_seq FROM prudent_goal_allocation ORDER BY recorded_seq DESC")) {
      while (rows.next()) {
        numbers.add(rows.getLong(1));
      }
    }
    return numbers;
  }

  /** The migration switches the append-only trigger off to fill the column; it must be on again. */
  private void assertRewritingIsStillRefused() throws SQLException {
    try (Connection owner = connect();
        Statement statement = owner.createStatement()) {
      SQLException refused =
          assertThrows(
              SQLException.class,
              () -> statement.executeUpdate("UPDATE prudent_goal_allocation SET note = 'x'"));
      assertTrue(
          refused.getMessage().contains("append-only"),
          "expected the history to refuse the change, got: " + refused.getMessage());
    }
  }
}
