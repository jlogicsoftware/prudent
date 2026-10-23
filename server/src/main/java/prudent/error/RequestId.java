package prudent.error;

import jakarta.enterprise.context.RequestScoped;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * The identifier of the request being served, carried in {@code X-Request-ID}.
 *
 * <p>It is what ties a response a user (or the client's log) holds to the one log line the server
 * wrote about the failure, which is how a failure is diagnosed without the log containing anything
 * about the request's contents.
 *
 * <p><strong>A caller's value is accepted only if it is boring.</strong> The id is written into a
 * log line and echoed into a response header, so a value with a newline would forge a log entry.
 * Anything outside {@link #ACCEPTABLE} is replaced, not repaired.
 */
@RequestScoped
public class RequestId {

  /** Header name; already in the CORS allow- and expose-lists. */
  public static final String HEADER = "X-Request-ID";

  static final Pattern ACCEPTABLE = Pattern.compile("[A-Za-z0-9._-]{1,64}");

  private String value;

  /** Adopts the caller's id if it is acceptable, otherwise mints one. */
  public void adopt(String supplied) {
    value = supplied != null && ACCEPTABLE.matcher(supplied).matches() ? supplied : generate();
  }

  /** The id, minted on first use if nothing adopted one (a failure before the filter ran). */
  public String value() {
    if (value == null) {
      value = generate();
    }
    return value;
  }

  private static String generate() {
    return UUID.randomUUID().toString();
  }
}
