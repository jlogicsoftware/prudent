package prudent.plan;

import java.util.List;
import prudent.error.PrudentException;
import prudent.proto.v1.Reminder;

/**
 * Whether a plan's occurrences should produce reminders, and how many days ahead (M5,
 * jlogicsoftware/prudent#40, ADR-054) — a validated value, the way {@link RecurrenceRule} is.
 *
 * <p><strong>A setting, not a reminder.</strong> Nothing here is stored per occurrence or sent
 * anywhere; the in-app reminder centre and the local notifications that read it are later M5 tasks.
 * It is therefore never read by a balance, a total or a plan's recurrence, and changing it leaves
 * a plan's occurrences exactly as they were.
 *
 * <p><strong>Off by default.</strong> The first local notification is also the moment a platform
 * asks for permission, and that prompt belongs to something the user asked for.
 *
 * <p><strong>The lead time is one of a closed set, and anything else is refused, not rounded.</strong>
 * A client that asks for four days and is quietly given three would show the user a setting that is
 * not the one in force. The lead time is kept while the reminder is disabled, so switching it off
 * and on again does not forget the user's choice.
 *
 * @param enabled whether this plan's occurrences produce reminders
 * @param leadDays whole calendar days before an occurrence's date, one of {@link #SUPPORTED}
 */
public record ReminderSetting(boolean enabled, int leadDays) {

  /** The lead times offered, in days: the day itself, one, two, three, and a week. */
  public static final List<Integer> SUPPORTED = List.of(0, 1, 2, 3, 7);

  /** The lead time a reminder starts with, and the one an omitted value means. */
  public static final int DEFAULT_LEAD_DAYS = 1;

  /** Disabled, one day ahead: what a plan has until the user says otherwise. */
  public static final ReminderSetting DEFAULT = new ReminderSetting(false, DEFAULT_LEAD_DAYS);

  public ReminderSetting {
    if (!SUPPORTED.contains(leadDays)) {
      throw PrudentException.invalid(
          "A reminder's lead time must be one of "
              + SUPPORTED.stream().map(String::valueOf).toList()
              + " days before the occurrence, not "
              + leadDays
              + ".");
    }
  }

  /**
   * The setting a wire {@link Reminder} describes, or a 400 naming the unsupported lead time.
   *
   * @param reminder the wire value
   * @param present whether the request carried a reminder at all; absent is {@link #DEFAULT}, not
   *     an error — a plan is useful without one
   */
  public static ReminderSetting fromProto(Reminder reminder, boolean present) {
    if (!present) {
      return DEFAULT;
    }
    // proto3 decodes an omitted number to 0, which here is a real lead time, so presence decides.
    // A value past Integer.MAX_VALUE saturates and is refused with the rest rather than wrapping
    // to a supported-looking negative.
    int leadDays =
        reminder.hasLeadDays()
            ? (int) Math.min(Integer.toUnsignedLong(reminder.getLeadDays()), Integer.MAX_VALUE)
            : DEFAULT_LEAD_DAYS;
    return new ReminderSetting(reminder.getEnabled(), leadDays);
  }
}
