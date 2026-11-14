package prudent.imports;

import java.util.EnumSet;
import java.util.Set;

/**
 * Where an import session is in its life — the persisted form of the wire {@code
 * ImportSessionState} (M6, jlogicsoftware/prudent#72, ADR-089). Named {@code State} here so it does
 * not collide with the generated wire enum it is converted to in {@link ImportMapper}.
 *
 * <p>Persisted by NAME; the table's {@code CHECK} lists the same names.
 *
 * <p><strong>The transitions are the whole rule, and they live here and nowhere else:</strong>
 *
 * <pre>
 *   PARSED ──► PREVIEWED ──► COMMITTED
 *   PREVIEWED ──► PREVIEWED             (previewed again, e.g. with another destination account)
 *   PARSED, PREVIEWED ──► DISCARDED     (the user threw it away)
 *   PARSED, PREVIEWED ──► EXPIRED       (not confirmed in time)
 * </pre>
 *
 * There is no way into PARSED except creating the session, which happens only after a parse that
 * succeeded; no way into COMMITTED except through PREVIEWED; and COMMITTED, DISCARDED and EXPIRED
 * are terminal, so a statement cannot be committed twice by this machine. The one edge back onto
 * itself is PREVIEWED to PREVIEWED: bytes are never kept, so a user who sees the preview and then
 * picks a different destination account would otherwise have to upload again. A preview that runs
 * again re-validates the destination and re-runs the preview stages. (Making a repeated commit an
 * idempotent success is jlogicsoftware/prudent#76's to decide; it changes the resource, not this
 * graph.)
 */
public enum ImportState {
  PARSED,
  PREVIEWED,
  COMMITTED,
  DISCARDED,
  EXPIRED;

  /** The states a session may move to from this one. */
  public Set<ImportState> successors() {
    return switch (this) {
      case PARSED -> EnumSet.of(PREVIEWED, DISCARDED, EXPIRED);
      case PREVIEWED -> EnumSet.of(PREVIEWED, COMMITTED, DISCARDED, EXPIRED);
      case COMMITTED, DISCARDED, EXPIRED -> EnumSet.noneOf(ImportState.class);
    };
  }

  public boolean canMoveTo(ImportState target) {
    return successors().contains(target);
  }

  /**
   * Whether a session in this state still holds its rows. The rows carry personal data, so every
   * other state has none (ADR-089).
   */
  public boolean holdsRows() {
    return this == PARSED || this == PREVIEWED;
  }
}
