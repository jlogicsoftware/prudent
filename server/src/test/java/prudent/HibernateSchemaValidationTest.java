package prudent;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.Test;

/**
 * Proves that every mapped entity agrees with the table Flyway built for it.
 *
 * <p><strong>Why a test.</strong> Hibernate never owns the schema here ({@code
 * schema-management.strategy=none}), so nothing in the test profile compares an entity with its
 * table. Quarkus does compare them after boot, but only in {@code %dev}, and only by logging an
 * {@code ERROR} while the server goes on to report that it started. A mapping that drifted from a
 * migration — a {@code CHAR(3)} column mapped as {@code VARCHAR}, say — therefore went unnoticed
 * until someone read a local startup log. This test runs the same check against the migrated
 * schema and fails the build instead.
 *
 * <p>The check is deliberately not switched off or narrowed anywhere: a mismatch is fixed in the
 * entity (or the migration), never silenced.
 */
@QuarkusTest
class HibernateSchemaValidationTest {

  @Inject SessionFactory sessionFactory;

  @Test
  void everyEntityMatchesItsMigratedTable() {
    assertDoesNotThrow(() -> sessionFactory.getSchemaManager().validate());
  }
}
