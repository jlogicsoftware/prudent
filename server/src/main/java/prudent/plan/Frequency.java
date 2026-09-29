package prudent.plan;

import prudent.proto.v1.RecurrenceFrequency;

/**
 * How often a plan repeats — the persisted form of the wire {@link RecurrenceFrequency}.
 *
 * <p>A separate enum rather than the generated one, for the reasons {@link
 * prudent.account.AccountKind} sets out: the generated enum carries {@code UNSPECIFIED} and {@code
 * UNRECOGNIZED}, neither of which is a frequency, and storing it directly would make "the client
 * forgot the field" a persistable row. Every {@code Frequency} has a wire form; not every wire
 * value has a {@code Frequency}.
 *
 * <p>Persisted by NAME, so the constants here are the column's vocabulary: renaming one is a data
 * migration, not a refactor.
 */
public enum Frequency {
  ONCE,
  DAILY,
  WEEKLY,
  MONTHLY,
  YEARLY;

  /**
   * The wire value this frequency is sent as. Total — every constant maps.
   *
   * @return the generated proto enum constant
   */
  public RecurrenceFrequency toProto() {
    return switch (this) {
      case ONCE -> RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE;
      case DAILY -> RecurrenceFrequency.RECURRENCE_FREQUENCY_DAILY;
      case WEEKLY -> RecurrenceFrequency.RECURRENCE_FREQUENCY_WEEKLY;
      case MONTHLY -> RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY;
      case YEARLY -> RecurrenceFrequency.RECURRENCE_FREQUENCY_YEARLY;
    };
  }

  /**
   * The frequency a wire value names, or {@code null} if it names none. The caller turns the
   * {@code null} into a refusal; nothing here quietly picks a default.
   *
   * @param frequency the wire value, possibly {@code null}
   * @return the matching frequency, or {@code null} for UNSPECIFIED and UNRECOGNIZED
   */
  public static Frequency fromProto(RecurrenceFrequency frequency) {
    if (frequency == null) {
      return null;
    }
    return switch (frequency) {
      case RECURRENCE_FREQUENCY_ONCE -> ONCE;
      case RECURRENCE_FREQUENCY_DAILY -> DAILY;
      case RECURRENCE_FREQUENCY_WEEKLY -> WEEKLY;
      case RECURRENCE_FREQUENCY_MONTHLY -> MONTHLY;
      case RECURRENCE_FREQUENCY_YEARLY -> YEARLY;
      case RECURRENCE_FREQUENCY_UNSPECIFIED, UNRECOGNIZED -> null;
    };
  }
}
