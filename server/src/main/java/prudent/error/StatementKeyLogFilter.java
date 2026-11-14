package prudent.error;

import io.quarkus.logging.LoggingFilter;
import java.util.logging.Filter;
import java.util.logging.LogRecord;

/**
 * Drops the log lines that quote a statement-row key (ADR-091). When the unique index
 * {@code prudent_record_import_key_unique} refuses a write, Postgres puts the offending values in
 * its message ("Key (account_id, import_fingerprint, import_occurrence)=(...)") and both Hibernate
 * and the transaction manager log that message, with the cause chain. The key is personal data and
 * must not reach the log.
 *
 * <p>Only those lines are dropped, matched on the column name Postgres always quotes with the value,
 * not on a logger: silencing a whole logger would also hide every other database or transaction
 * warning. The failure itself is not lost: it still propagates to the caller and
 * {@link UnhandledExceptionMapper} logs it as one line without the message.
 */
@LoggingFilter(name = "prudent-statement-key")
public class StatementKeyLogFilter implements Filter {

  /** The column that Postgres names next to the key's value. */
  static final String COLUMN = "import_fingerprint";

  @Override
  public boolean isLoggable(LogRecord record) {
    if (mentions(record.getMessage())) {
      return false;
    }
    Object[] parameters = record.getParameters();
    if (parameters != null) {
      for (Object parameter : parameters) {
        if (parameter != null && mentions(String.valueOf(parameter))) {
          return false;
        }
      }
    }
    for (Throwable cause = record.getThrown(); cause != null; cause = cause.getCause()) {
      if (mentions(cause.getMessage())) {
        return false;
      }
      if (cause.getCause() == cause) {
        break;
      }
    }
    return true;
  }

  private static boolean mentions(String text) {
    return text != null && text.contains(COLUMN);
  }
}
