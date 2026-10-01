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
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for {@code prudent_category.archived_at} (V20261004090000, ADR-047): the
 * column exists, is nullable, and a writer that has never heard of it still produces an ACTIVE
 * category — which is what every row that predates the migration is.
 *
 * <p>Plain SQL through the owner connection on purpose, as in {@link BudgetSchemaTest}: the point
 * is what the schema does when nothing in Java has set the column.
 */
@QuarkusTest
class CategoryArchiveSchemaTest {

  @Inject DataSource dataSource;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  private UUID insertWithoutArchivedAt() throws SQLException {
    UUID id = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        PreparedStatement insert =
            owner.prepareStatement(
                "INSERT INTO prudent_category (id, user_id, title, icon_key, description,"
                    + " color_argb) VALUES (?, ?, 'Old', 'food', '', 4278190080)")) {
      insert.setObject(1, id);
      insert.setObject(2, UUID.fromString(PrudentTest.ALICE));
      insert.executeUpdate();
    }
    return id;
  }

  private Timestamp archivedAt(UUID id) throws SQLException {
    try (Connection owner = dataSource.getConnection();
        PreparedStatement select =
            owner.prepareStatement("SELECT archived_at FROM prudent_category WHERE id = ?")) {
      select.setObject(1, id);
      try (ResultSet rows = select.executeQuery()) {
        assertTrue(rows.next(), "the category must exist");
        return rows.getTimestamp(1);
      }
    }
  }

  @Test
  void aCategoryWrittenWithoutTheColumnIsActive() throws SQLException {
    assertNull(archivedAt(insertWithoutArchivedAt()));
  }

  @Test
  void theColumnHoldsATimestampAndCanBeClearedAgain() throws SQLException {
    UUID id = insertWithoutArchivedAt();
    Instant when = Instant.parse("2026-10-01T12:00:00Z");
    try (Connection owner = dataSource.getConnection();
        PreparedStatement update =
            owner.prepareStatement("UPDATE prudent_category SET archived_at = ? WHERE id = ?")) {
      update.setTimestamp(1, Timestamp.from(when));
      update.setObject(2, id);
      update.executeUpdate();
    }
    assertEquals(when, archivedAt(id).toInstant());

    try (Connection owner = dataSource.getConnection();
        PreparedStatement update =
            owner.prepareStatement("UPDATE prudent_category SET archived_at = NULL WHERE id = ?")) {
      update.setObject(1, id);
      update.executeUpdate();
    }
    assertNull(archivedAt(id));
  }
}
