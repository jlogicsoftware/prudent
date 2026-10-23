package prudent.error;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

/**
 * Turns a server failure into one log line that says where it happened and what kind it was, and
 * nothing about the data it was handling.
 *
 * <p><strong>Why not log the exception.</strong> A stack trace prints each exception's
 * <em>message</em>, and a database's message can quote the row it refused: Postgres puts the whole
 * failing row, amounts included, in the detail of a NOT NULL or CHECK violation. Class names,
 * the SQLSTATE and a source location are code and codes, not data; they are enough to find the
 * failing line, which is what a diagnosis starts from.
 *
 * <p>What is recorded: the request id, the HTTP method, the handler (class and method, not the
 * path — a path carries record ids and the query string carries filter amounts), the status, the
 * exception classes from the outermost to the root cause, the SQLSTATE if any, and the first
 * Prudent source location on the root cause's trace.
 */
public final class ServerFailureReport {

  private static final int MAX_CHAIN = 8;

  private ServerFailureReport() {}

  /** The full line for a failed request. */
  public static String describe(
      String requestId, String httpMethod, String handler, int status, Throwable failure) {
    return "request="
        + requestId
        + " method="
        + httpMethod
        + " handler="
        + handler
        + " status="
        + status
        + " "
        + describeFailure(failure);
  }

  /** The failure alone: chain, SQLSTATE, location. */
  public static String describeFailure(Throwable failure) {
    List<String> chain = new ArrayList<>();
    String sqlState = null;
    Throwable root = failure;
    for (Throwable t = failure; t != null && chain.size() < MAX_CHAIN; t = t.getCause()) {
      chain.add(t.getClass().getName());
      root = t;
      if (sqlState == null && t instanceof SQLException sql && sql.getSQLState() != null) {
        sqlState = sql.getSQLState();
      }
      if (t.getCause() == t) {
        break;
      }
    }
    StringBuilder out = new StringBuilder("failure=").append(String.join(" <- ", chain));
    if (sqlState != null) {
      out.append(" sqlstate=").append(sqlState);
    }
    String at = location(root);
    if (at != null) {
      out.append(" at=").append(at);
    }
    return out.toString();
  }

  /** First frame in Prudent's own code, else the first frame at all. */
  private static String location(Throwable root) {
    StackTraceElement[] trace = root.getStackTrace();
    if (trace.length == 0) {
      return null;
    }
    for (StackTraceElement frame : trace) {
      if (frame.getClassName().startsWith("prudent.")) {
        return frame.toString();
      }
    }
    return trace[0].toString();
  }
}
