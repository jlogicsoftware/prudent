package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.logging.LoggingFilter;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import java.sql.SQLException;
import java.util.UUID;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import org.eclipse.microprofile.config.ConfigProvider;
import org.junit.jupiter.api.Test;
import prudent.error.StatementKeyLogFilter;
import prudent.record.RecordEntity;

/**
 * A unique-index violation on the statement-row key must not write the key into the log (ADR-091):
 * Postgres quotes the row's values in its message, and Hibernate and Narayana log that message and
 * its causes. Three things are checked, and the gap between them is stated: the violation is still
 * refused to the caller; the filter drops a record shaped like the real ones (message, parameters,
 * or any cause) and keeps unrelated ones; and the filter is the one the console handler is
 * configured with. That the running console handler then applies it is Quarkus's own contract and is
 * not exercised here, because the test JVM's logging is not the application's.
 */
@QuarkusTest
class ImportKeyLoggingTest {

  private static final String DIGEST = "c".repeat(64);
  private static final String POSTGRES_MESSAGE =
      "ERROR: duplicate key value violates unique constraint \"prudent_record_import_key_unique\"\n"
          + "  Detail: Key (account_id, import_fingerprint, import_occurrence)=(00000000-0000-0000-0000-000000000000, v1:"
          + DIGEST
          + ", 1) already exists.";

  private final StatementKeyLogFilter filter = new StatementKeyLogFilter();

  @Test
  void aKeyCollisionIsStillRefusedToTheCaller() {
    PrudentTest.reset();
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    write(account);

    assertThrows(RuntimeException.class, () -> write(account));
  }

  @Test
  void theFilterDropsEveryShapeTheKeyArrivesIn() {
    LogRecord inMessage = new LogRecord(Level.WARNING, POSTGRES_MESSAGE);
    LogRecord inParameter = new LogRecord(Level.WARNING, "could not execute: {0}");
    inParameter.setParameters(new Object[] {POSTGRES_MESSAGE});
    LogRecord inCause = new LogRecord(Level.WARNING, "ARJUNA012125: beforeCompletion failed");
    inCause.setThrown(
        new RuntimeException(
            "could not execute statement", new RuntimeException(new SQLException(POSTGRES_MESSAGE))));

    assertFalse(filter.isLoggable(inMessage));
    assertFalse(filter.isLoggable(inParameter));
    assertFalse(filter.isLoggable(inCause));
  }

  @Test
  void theFilterKeepsUnrelatedRecords() {
    assertTrue(filter.isLoggable(new LogRecord(Level.SEVERE, "connection refused")));
    LogRecord other = new LogRecord(Level.WARNING, "rolled back");
    other.setThrown(new IllegalStateException("not the key"));
    assertTrue(filter.isLoggable(other));
  }

  @Test
  void theConsoleHandlerIsConfiguredWithThatFilter() {
    String name = StatementKeyLogFilter.class.getAnnotation(LoggingFilter.class).name();
    assertEquals(
        name,
        ConfigProvider.getConfig().getValue("quarkus.log.console.filter", String.class));
  }

  private static void write(UUID account) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity record = new RecordEntity();
              record.id = UUID.randomUUID();
              record.userId = UUID.fromString(PrudentTest.ALICE);
              record.accountId = account;
              record.title = "Imported";
              record.amountMinor = -1;
              record.currency = "PLN";
              record.date = java.time.LocalDate.of(2026, 10, 1);
              record.importFingerprint = "v1:" + DIGEST;
              record.importOccurrence = 1;
              record.persist();
            });
  }
}
