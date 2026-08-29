package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Proves that Prudent's tables have row-level security <em>and</em> that the policies actually admit
 * the application — <strong>by connecting as {@code zen_runtime} and reading, not by reading the
 * migration.</strong>
 *
 * <p><strong>Why asserting on the SQL text would prove nothing.</strong> The migration is the
 * control; a test over its contents would only establish that the text is what the text is. What
 * has to be true is a runtime property of a real connection, so everything below runs real SQL
 * against the Dev Services database the rest of the suite uses.
 *
 * <p><strong>Why "the insert did not throw" is not the assertion.</strong> This is the failure mode
 * the whole arrangement exists to prevent: RLS enabled with no policy for the application role does
 * not raise — it returns ZERO ROWS. A subsystem reading an empty table reports success while doing
 * nothing, so the only assertion that distinguishes a working policy from a missing one is a
 * <em>row count read back through the constrained role</em>. That is what
 * {@link #applicationRole_canReadEveryPrudentTable} does, and dropping any one policy makes it fail.
 *
 * <p>Two things this test supplies that production does not, both honest about what they stand in
 * for: a <strong>login</strong> for {@code zen_runtime} (the migration deliberately creates it
 * {@code NOLOGIN} and without a password, because a credential in a migration is plaintext in git —
 * production's is provisioned out of band), and the seeded rows themselves.
 */
@QuarkusTest
class PrudentRowLevelSecurityTest {

  private static final String[] PRUDENT_TABLES = {
    "prudent_account", "prudent_account_balance", "prudent_category", "prudent_record",
    "prudent_settings"
  };

  private static final String RUNTIME_PASSWORD = "test-only-throwaway";

  @Inject DataSource dataSource;

  private String jdbcUrl;

  @BeforeEach
  void grantATemporaryLogin() throws SQLException {
    PrudentTest.reset();
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 12_34L, "PLN");
    PrudentTest.seedSettings(PrudentTest.ALICE, "PLN");

    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      jdbcUrl = owner.getMetaData().getURL();
      statement.execute("ALTER ROLE zen_runtime LOGIN PASSWORD '" + RUNTIME_PASSWORD + "'");
    }
  }

  @AfterEach
  void revokeTheTemporaryLogin() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      statement.execute("ALTER ROLE zen_runtime NOLOGIN PASSWORD NULL");
    }
  }

  @Test
  void everyPrudentTableHasRowLevelSecurityEnabled() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      for (String table : PRUDENT_TABLES) {
        try (ResultSet rows =
            statement.executeQuery(
                "SELECT relrowsecurity, relforcerowsecurity FROM pg_class"
                    + " WHERE relname = '" + table + "'"
                    + " AND relnamespace = 'public'::regnamespace")) {
          assertTrue(rows.next(), table + " must exist");
          assertTrue(
              rows.getBoolean("relrowsecurity"),
              table
                  + " has no row-level security. A table created in public is served by Supabase's"
                  + " Data API to anyone holding the project's anon key.");
          // FORCE would make the owner subject to its own policies, so a migration could lock the
          // schema out of its own tables. Deliberately not set, and asserted so that "not set"
          // reads as a decision rather than an absence.
          assertEquals(
              false,
              rows.getBoolean("relforcerowsecurity"),
              table + " must not FORCE row-level security; the owner has to keep bypassing.");
        }
      }
    }
  }

  @Test
  void applicationRole_canReadEveryPrudentTable() throws SQLException {
    // THE TEST THAT FAILS IF A POLICY IS MISSING. Without a zen_runtime policy each count below is
    // 0 rather than an error, which is exactly what makes the omission invisible in production.
    try (Connection runtime = connectAsRuntime()) {
      assertRowCount(runtime, "prudent_account", 1);
      assertRowCount(runtime, "prudent_account_balance", 1);
      assertRowCount(runtime, "prudent_category", 1);
      assertRowCount(runtime, "prudent_record", 1);
      assertRowCount(runtime, "prudent_settings", 1);
    }
  }

  @Test
  void applicationRole_canWriteAndReadBackItsOwnWrite() throws SQLException {
    // A policy that permitted SELECT but not INSERT would pass the read test above on seeded data
    // and fail every actual save. WITH CHECK (true) is what covers the write half, so the write
    // half is asserted.
    try (Connection runtime = connectAsRuntime();
        Statement statement = runtime.createStatement()) {
      UUID id = UUID.randomUUID();
      statement.execute(
          "INSERT INTO prudent_category (id, user_id, title, icon_key, description, color_argb)"
              + " VALUES ('" + id + "', '" + PrudentTest.ALICE + "', 'Written by zen_runtime',"
              + " 'work', '', 4278190080)");

      try (ResultSet rows =
          statement.executeQuery("SELECT count(*) FROM prudent_category WHERE id = '" + id + "'")) {
        assertTrue(rows.next());
        assertEquals(
            1,
            rows.getInt(1),
            "zen_runtime wrote a row it cannot read back: the policy admits INSERT but not SELECT,"
                + " which in the application looks like a save that silently did nothing.");
      }
    }
  }

  @Test
  void applicationRole_cannotRewriteMigrationHistory() throws SQLException {
    // zen-identity's role migration revokes flyway_schema_history from zen_runtime: an application
    // role that can rewrite migration history can make the schema claim to be any version it likes.
    // Asserted here because Prudent's tables arriving in that schema is what makes it Prudent's
    // concern too.
    try (Connection runtime = connectAsRuntime();
        Statement statement = runtime.createStatement()) {
      statement.executeQuery("SELECT count(*) FROM flyway_schema_history");
      fail("zen_runtime must not be able to read flyway_schema_history");
    } catch (SQLException refused) {
      assertTrue(
          refused.getMessage().toLowerCase().contains("permission denied"),
          "expected a permission error, got: " + refused.getMessage());
    }
  }

  private Connection connectAsRuntime() throws SQLException {
    return DriverManager.getConnection(jdbcUrl, "zen_runtime", RUNTIME_PASSWORD);
  }

  private static void assertRowCount(Connection connection, String table, int expected)
      throws SQLException {
    try (Statement statement = connection.createStatement();
        ResultSet rows = statement.executeQuery("SELECT count(*) FROM " + table)) {
      assertTrue(rows.next());
      assertEquals(
          expected,
          rows.getInt(1),
          "zen_runtime read "
              + rows.getInt(1)
              + " rows from "
              + table
              + " but the table holds "
              + expected
              + ". A policy-less RLS returns zero rows rather than raising, so this is what a"
              + " missing zen_runtime policy looks like — and in production it looks like an empty"
              + " account list, not like an error.");
    }
  }
}
