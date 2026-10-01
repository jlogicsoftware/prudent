package prudent.goal;

/**
 * What an envelope entry did — the persisted form of the wire {@code GoalAllocationKind} (M4,
 * jlogicsoftware/prudent#64, ADR-050). Named without the {@code Goal} prefix only so it does not
 * collide with the generated wire enum it is converted to in {@link GoalAllocationMapper}.
 *
 * <p>Persisted by NAME, so renaming a constant is a data migration, not a refactor; the table's
 * {@code CHECK} lists the same names.
 *
 * <p>The kind decides which goals an entry names, and that is the whole rule, held here once: an
 * {@link #ALLOCATE} has only a target, a {@link #WITHDRAW} only a source, and a {@link #MOVE} both.
 */
public enum AllocationKind {
  /** Money set aside for a goal. */
  ALLOCATE(false, true),
  /** Money released from a goal. */
  WITHDRAW(true, false),
  /** Money reassigned from one goal to another, as one entry. */
  MOVE(true, true);

  private final boolean hasSource;
  private final boolean hasTarget;

  AllocationKind(boolean hasSource, boolean hasTarget) {
    this.hasSource = hasSource;
    this.hasTarget = hasTarget;
  }

  /** Whether an entry of this kind takes money out of a goal's envelope. */
  public boolean hasSource() {
    return hasSource;
  }

  /** Whether an entry of this kind puts money into a goal's envelope. */
  public boolean hasTarget() {
    return hasTarget;
  }
}
