package prudent.plan;

import java.util.EnumSet;
import java.util.Set;

/**
 * What became of a generated occurrence — the persisted form of the stored part of the wire {@code
 * OccurrenceStatus} (M2, jlogicsoftware/prudent#56, ADR-039).
 *
 * <p>Only what the server <em>stores</em>. "Overdue" is not a constant here: it is {@link
 * #PLANNED} plus a date that has passed in the plan's time zone, decided by {@link
 * OccurrenceResource} when it reads, so it can never go stale.
 *
 * <p>Persisted by NAME, so renaming a constant is a data migration, not a refactor.
 *
 * <p><strong>The transitions are the whole rule, and they live here and nowhere else:</strong>
 *
 * <pre>
 *   PLANNED ──► SKIPPED ──► PLANNED        (skip, and restore)
 *   PLANNED ──► COMPLETED                  (confirmation, #57; terminal)
 * </pre>
 *
 * A completed occurrence has become an actual transaction, so it is final: reopening it would have
 * to undo that transaction, which is confirmation's decision to make and not a state flip's.
 * Staying in the same state is not a transition either — a second skip is refused rather than
 * quietly accepted, so a client that thinks it is skipping something open finds out that it is not.
 */
public enum OccurrenceState {
  PLANNED,
  COMPLETED,
  SKIPPED;

  /** The states an occurrence may move to from this one. */
  public Set<OccurrenceState> successors() {
    return switch (this) {
      case PLANNED -> EnumSet.of(SKIPPED, COMPLETED);
      case SKIPPED -> EnumSet.of(PLANNED);
      case COMPLETED -> EnumSet.noneOf(OccurrenceState.class);
    };
  }

  /** Whether {@code target} is a valid next state for an occurrence that is in this one. */
  public boolean canTransitionTo(OccurrenceState target) {
    return successors().contains(target);
  }
}
