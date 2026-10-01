package prudent.goal;

import java.util.EnumSet;
import java.util.Set;

/**
 * Where a goal is in its life — the persisted form of the wire {@code GoalStatus} (M4,
 * jlogicsoftware/prudent#38, ADR-049). Named {@code State} here only so it does not collide with
 * the generated wire enum it is converted to and from in {@link GoalMapper}.
 *
 * <p>Persisted by NAME, so renaming a constant is a data migration, not a refactor; the table's
 * {@code CHECK} lists the same names.
 *
 * <p><strong>The transitions are the whole rule, and they live here and nowhere else:</strong>
 *
 * <pre>
 *   ACTIVE ──► COMPLETED                     (complete)
 *   ACTIVE ──► ARCHIVED                      (archive)
 *   COMPLETED ──► ARCHIVED                   (archive)
 *   COMPLETED ──► ACTIVE, ARCHIVED ──► ACTIVE   (reactivate)
 * </pre>
 *
 * Nothing is terminal, because nothing is ever deleted: a goal marked reached by mistake, or
 * archived and wanted again, is brought back rather than recreated, which would orphan the history
 * hanging off the original. Staying in the same state is not a transition — a second archive is
 * refused rather than quietly accepted, so a client that believes it changed something finds out
 * that it did not.
 */
public enum GoalState {
  ACTIVE,
  COMPLETED,
  ARCHIVED;

  /** The states a goal may move to from this one. */
  public Set<GoalState> successors() {
    return switch (this) {
      case ACTIVE -> EnumSet.of(COMPLETED, ARCHIVED);
      case COMPLETED -> EnumSet.of(ACTIVE, ARCHIVED);
      case ARCHIVED -> EnumSet.of(ACTIVE);
    };
  }

  public boolean canMoveTo(GoalState target) {
    return successors().contains(target);
  }

  /**
   * Whether money may be put into an envelope in this state (ADR-050). Only a goal still being
   * saved for: a completed goal has reached its target and an archived one is retired.
   */
  public boolean acceptsMoney() {
    return this == ACTIVE;
  }

  /**
   * Whether money may be taken out of an envelope in this state (ADR-050). A completed goal can
   * still release what is left in it; an archived goal is read-only, so it cannot.
   */
  public boolean releasesMoney() {
    return this != ARCHIVED;
  }
}
