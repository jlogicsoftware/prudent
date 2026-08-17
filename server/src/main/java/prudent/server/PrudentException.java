package prudent.server;

import jakarta.ws.rs.core.Response.Status;

/**
 * A refusal Prudent's domain makes, carrying the HTTP status and the stable {@code code} the client
 * matches on.
 *
 * <p><strong>Why an exception rather than each resource building its own {@code Response}.</strong>
 * Every refusal in this server has to arrive at the client as the same shape — a {@code ZenError}
 * body in whichever transport format the caller negotiated. Spreading that construction across
 * twenty call sites is twenty chances for one of them to answer with a bare status and no body, and
 * a client parsing {@code ZenError} on any status ≥ 400 would then read an empty body as a decode
 * failure. Throwing puts the shape in exactly one place: {@link PrudentExceptionMapper}.
 *
 * <p><strong>The {@code code} is API, the message is not.</strong> A client branches on
 * {@code code}; the message is for a human reading a log or a developer console. Adding a code is a
 * contract change in everything but name, which is why they are constants here rather than string
 * literals at the throw sites.
 */
public class PrudentException extends RuntimeException {

  /** The row named by the request does not exist, or is not the caller's. */
  public static final String NOT_FOUND = "not_found";

  /** The request is structurally fine but says something the domain refuses. */
  public static final String INVALID = "invalid";

  /** The request would break a rule that protects existing data (a delete that would orphan it). */
  public static final String CONFLICT = "conflict";

  private final String code;
  private final Status status;

  private PrudentException(String code, Status status, String message) {
    super(message);
    this.code = code;
    this.status = status;
  }

  /**
   * A 404 for a row that does not exist <em>or</em> is not the caller's — deliberately the same
   * answer for both.
   *
   * <p>Answering 403 for "exists but belongs to someone else" would confirm the row exists to
   * someone who cannot see it, turning any id into an existence oracle. The caller learns only that
   * <em>they</em> have no such row, which is the true statement.
   *
   * @param what the resource kind, for the human-readable message only
   * @param id the id that was not found, for the message only
   */
  public static PrudentException notFound(String what, Object id) {
    return new PrudentException(
        NOT_FOUND, Status.NOT_FOUND, "No such " + what + " for this user: " + id);
  }

  /** A 400 for a request the domain refuses on its contents. */
  public static PrudentException invalid(String message) {
    return new PrudentException(INVALID, Status.BAD_REQUEST, message);
  }

  /** A 409 for a request that would orphan or contradict data that already exists. */
  public static PrudentException conflict(String message) {
    return new PrudentException(CONFLICT, Status.CONFLICT, message);
  }

  /** The stable code the client branches on. */
  public String code() {
    return code;
  }

  /** The HTTP status this refusal is served at. */
  public Status status() {
    return status;
  }
}
