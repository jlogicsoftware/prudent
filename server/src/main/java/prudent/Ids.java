package prudent;

import java.util.UUID;
import prudent.error.PrudentException;

/**
 * Parsing an id out of a URL path, with the one behaviour that matters: a malformed id is a
 * <em>refusal</em>, never a {@code null} that flows onward.
 *
 * <p><strong>Why this is not just {@code UUID.fromString}.</strong> That method throws
 * {@link IllegalArgumentException}, which JAX-RS renders as a bare 500 with no body — so a client
 * sending a typo'd id would get "internal server error" and a {@code ZenClient} expecting to parse
 * {@code ZenError} on any status ≥ 400 would find an empty body and report a decode failure. The
 * cause and the symptom would have nothing to do with each other.
 *
 * <p>Answering 404 rather than 400 is deliberate: to the caller, "that is not a well-formed id" and
 * "you have no row with that id" are the same fact — they have no such row — and giving them one
 * answer means the not-found path cannot be told apart from the malformed path by probing.
 */
public final class Ids {

  private Ids() {}

  /**
   * The UUID a path segment names.
   *
   * @param what the resource kind, for the message only
   * @param id the raw path segment
   * @return the parsed id, never {@code null}
   * @throws PrudentException 404, if the segment is missing or not a UUID
   */
  public static UUID parse(String what, String id) {
    if (id == null || id.isBlank()) {
      throw PrudentException.notFound(what, id);
    }
    try {
      return UUID.fromString(id);
    } catch (IllegalArgumentException notAUuid) {
      // Converted to the domain's own refusal, not swallowed: the caller gets a ZenError body at a
      // status that describes their situation, instead of a 500 that describes ours.
      throw PrudentException.notFound(what, id);
    }
  }

  /**
   * The UUID a <em>request body field</em> names — the same parse, answered at 400 instead of 404.
   *
   * <p>The status differs because the question differs, and conflating them would mislead. A
   * malformed id in the PATH means "you asked for a thing that cannot exist", which is a 404. A
   * malformed id in the BODY means the body is wrong — the request is not asking for that row, it
   * is asking to <em>create or update</em> one that points at it — and answering 404 there would
   * tell a client the record it is trying to write does not exist, which is both true and entirely
   * beside the point.
   *
   * @param what the field's subject, for the message only
   * @param id the raw value from the request body
   * @return the parsed id, never {@code null}
   * @throws PrudentException 400, if the value is missing or not a UUID
   */
  public static UUID parseInBody(String what, String id) {
    if (id == null || id.isBlank()) {
      throw PrudentException.invalid("A record needs a " + what + ".");
    }
    try {
      return UUID.fromString(id);
    } catch (IllegalArgumentException notAUuid) {
      throw PrudentException.invalid("'" + id + "' is not a valid " + what + " id.");
    }
  }
}
