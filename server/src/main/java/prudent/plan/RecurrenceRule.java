package prudent.plan;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import prudent.error.PrudentException;
import prudent.proto.v1.Recurrence;

/**
 * When a plan's occurrences fall (M2, jlogicsoftware/prudent#34, ADR-037) — a validated value, and
 * the one place the date arithmetic lives.
 *
 * <p><strong>Every occurrence is a civil date</strong>, like {@code Record.date}. The n-th one is
 * computed <em>from {@link #startDate}</em>, never by stepping from the one before it: {@code
 * LocalDate.plusMonths} clamps 31 January to 28 February, and a rule that stepped from there would
 * fall on the 28th for the rest of its life. Computing from the anchor gives 31 January, 28
 * February, 31 March — the month-end the user chose — and makes every occurrence a pure function of
 * the rule and its index, which is what lets generation be repeated and still agree with itself
 * (jlogicsoftware/prudent#55).
 *
 * <p><strong>The time zone does not move any date.</strong> It decides which calendar day is
 * <em>today</em> for this plan ({@link #today}), and so when an occurrence is due and when it is
 * overdue. Occurrence dates themselves are zone-free.
 *
 * <p>Construction validates every invariant and refuses with a {@link PrudentException} (400), so a
 * rule that exists is a rule the arithmetic below can answer for. The migration holds the same
 * structural invariants as {@code CHECK} constraints.
 *
 * @param frequency how often it repeats; {@link Frequency#ONCE} for a one-off
 * @param interval every {@code interval} units of {@code frequency}; exactly 1 for ONCE
 * @param startDate the first occurrence and the anchor for every later one
 * @param timeZone the IANA zone in which "today" is reckoned for this plan
 * @param untilDate the last date an occurrence may fall on, inclusive; or {@code null}
 * @param occurrenceCount the total number of occurrences; or {@code null}
 */
public record RecurrenceRule(
    Frequency frequency,
    int interval,
    LocalDate startDate,
    ZoneId timeZone,
    LocalDate untilDate,
    Integer occurrenceCount) {

  /**
   * The largest interval accepted. Far beyond any real schedule — every thousand years — and
   * bounded so {@code index * interval} can never be the thing that overflows.
   */
  public static final int MAX_INTERVAL = 1000;

  /** The largest occurrence count accepted: daily for over twenty-seven years. */
  public static final int MAX_OCCURRENCES = 10_000;

  public RecurrenceRule {
    if (frequency == null) {
      throw PrudentException.invalid(
          "A plan needs a recurrence frequency: once, daily, weekly, monthly or yearly.");
    }
    if (startDate == null) {
      throw PrudentException.invalid("A plan needs a start date, as ISO-8601 YYYY-MM-DD.");
    }
    if (timeZone == null) {
      throw PrudentException.invalid("A plan needs an explicit IANA time zone, e.g. Europe/Warsaw.");
    }
    if (untilDate != null && occurrenceCount != null) {
      throw PrudentException.invalid(
          "A plan can end on a date or after a number of occurrences, not both.");
    }
    if (frequency == Frequency.ONCE) {
      if (interval != 1) {
        throw PrudentException.invalid("A one-off plan has no repeat interval.");
      }
      if (untilDate != null || occurrenceCount != null) {
        throw PrudentException.invalid(
            "A one-off plan has exactly one occurrence and takes no end condition.");
      }
    } else if (interval < 1 || interval > MAX_INTERVAL) {
      // 0 is what proto3 decodes an omitted interval to, so it is refused rather than read as 1:
      // "the client forgot" and "every period" must not become the same stored rule.
      throw PrudentException.invalid(
          "A repeating plan needs an interval from 1 to " + MAX_INTERVAL + ".");
    }
    if (untilDate != null && untilDate.isBefore(startDate)) {
      throw PrudentException.invalid("A plan cannot end before its start date.");
    }
    if (occurrenceCount != null && (occurrenceCount < 1 || occurrenceCount > MAX_OCCURRENCES)) {
      throw PrudentException.invalid(
          "A plan's occurrence count must be from 1 to " + MAX_OCCURRENCES + ".");
    }
  }

  /**
   * The rule a wire {@link Recurrence} describes, or a 400 naming what is wrong with it.
   *
   * @param recurrence the wire value; an absent message is refused, not defaulted
   * @param present whether the request carried the recurrence at all
   * @return the validated rule
   */
  public static RecurrenceRule fromProto(Recurrence recurrence, boolean present) {
    if (!present) {
      throw PrudentException.invalid("A plan needs a recurrence.");
    }
    Frequency frequency = Frequency.fromProto(recurrence.getFrequency());
    // An omitted interval is 0 on the wire. For ONCE it does not apply, so 0 and 1 both mean "the
    // one occurrence"; for a repeating frequency 0 reaches the constructor and is refused there.
    int interval = frequency == Frequency.ONCE && recurrence.getInterval() == 0
        ? 1
        : saturatedInt(recurrence.getInterval());
    LocalDate until =
        recurrence.getEndCase() == Recurrence.EndCase.UNTIL_DATE
            ? parseDate(recurrence.getUntilDate(), "until date")
            : null;
    Integer count =
        recurrence.getEndCase() == Recurrence.EndCase.OCCURRENCE_COUNT
            ? saturatedInt(recurrence.getOccurrenceCount())
            : null;
    return new RecurrenceRule(
        frequency,
        interval,
        parseDate(recurrence.getStartDate(), "start date"),
        parseZone(recurrence.getTimeZone()),
        until,
        count);
  }

  /**
   * An IANA region id such as {@code Europe/Warsaw}, or a 400.
   *
   * <p>Checked against the tz database's own list rather than accepted by whatever {@link
   * ZoneId#of} will parse, because that also admits fixed offsets ({@code +02:00}, {@code Z},
   * {@code GMT+2}). A fixed offset does not follow daylight saving, so for most places it would be
   * used for it names the right day for only half the year — and it would look deliberate.
   */
  public static ZoneId parseZone(String id) {
    if (id == null || id.isBlank()) {
      throw PrudentException.invalid("A plan needs an explicit IANA time zone, e.g. Europe/Warsaw.");
    }
    if (!ZoneId.getAvailableZoneIds().contains(id)) {
      throw PrudentException.invalid(
          "'" + id + "' is not an IANA time zone such as Europe/Warsaw. Fixed offsets are not"
              + " accepted: they do not follow daylight saving.");
    }
    return ZoneId.of(id);
  }

  /**
   * The {@code index}-th occurrence (0-based), computed from the anchor — ignoring the end
   * condition, which {@link #isWithinEnd} applies.
   */
  public LocalDate occurrence(long index) {
    if (index < 0) {
      throw new IllegalArgumentException("An occurrence index is never negative: " + index);
    }
    long step = index * interval;
    return switch (frequency) {
      case ONCE -> startDate;
      case DAILY -> startDate.plusDays(step);
      case WEEKLY -> startDate.plusWeeks(step);
      case MONTHLY -> startDate.plusMonths(step);
      case YEARLY -> startDate.plusYears(step);
    };
  }

  /** Whether the {@code index}-th occurrence, falling on {@code date}, is inside the end condition. */
  private boolean isWithinEnd(long index, LocalDate date) {
    if (frequency == Frequency.ONCE) {
      return index == 0;
    }
    if (occurrenceCount != null) {
      return index < occurrenceCount;
    }
    return untilDate == null || !date.isAfter(untilDate);
  }

  /**
   * Every occurrence in {@code [from, to]}, inclusive, in date order. The window is what bounds a
   * rule with no end; a caller never asks for "all of them".
   *
   * @throws IllegalArgumentException if {@code to} is before {@code from}
   */
  public List<LocalDate> occurrencesBetween(LocalDate from, LocalDate to) {
    if (to.isBefore(from)) {
      throw new IllegalArgumentException("Window ends (" + to + ") before it starts (" + from + ")");
    }
    List<LocalDate> dates = new ArrayList<>();
    for (long index = firstIndexNotAfter(from); ; index++) {
      LocalDate date;
      try {
        date = occurrence(index);
      } catch (DateTimeException pastTheCalendar) {
        // Beyond LocalDate.MAX: there are no later occurrences for any window to contain.
        break;
      }
      if (date.isAfter(to) || !isWithinEnd(index, date)) {
        break;
      }
      if (!date.isBefore(from)) {
        dates.add(date);
      }
    }
    return dates;
  }

  /**
   * An index whose occurrence is on or before {@code from} — a safe place to start scanning, so a
   * daily rule anchored years ago does not walk every day since. Conservative by one period for
   * months and years, where clamping makes the exact index awkward to state.
   */
  private long firstIndexNotAfter(LocalDate from) {
    if (frequency == Frequency.ONCE || !from.isAfter(startDate)) {
      return 0;
    }
    long periods = switch (frequency) {
      case DAILY -> ChronoUnit.DAYS.between(startDate, from);
      case WEEKLY -> ChronoUnit.WEEKS.between(startDate, from);
      case MONTHLY -> ChronoUnit.MONTHS.between(startDate, from);
      case YEARLY -> ChronoUnit.YEARS.between(startDate, from);
      case ONCE -> 0;
    };
    return Math.max(0, periods / interval - 1);
  }

  /**
   * The calendar day it is for this plan at {@code now} — the one thing the time zone decides.
   * An occurrence dated on or before it is due; one dated before it and still open is overdue.
   */
  public LocalDate today(Instant now) {
    return LocalDate.ofInstant(now, timeZone);
  }

  private static LocalDate parseDate(String date, String what) {
    if (date == null || date.isBlank()) {
      throw PrudentException.invalid("A plan needs a " + what + ", as ISO-8601 YYYY-MM-DD.");
    }
    try {
      return LocalDate.parse(date);
    } catch (DateTimeParseException malformed) {
      // Refused, never rolled forward: 2026-02-30 is not a date the user chose.
      throw PrudentException.invalid(
          "'" + date + "' is not an ISO-8601 " + what + ". Expected YYYY-MM-DD.");
    }
  }

  /**
   * A wire uint32 arrives in a Java {@code int} and reads NEGATIVE above 2^31. Saturating keeps
   * such a value too large rather than letting it wrap into a small valid one, so the range checks
   * above refuse it.
   */
  private static int saturatedInt(int unsigned) {
    return unsigned < 0 ? Integer.MAX_VALUE : unsigned;
  }
}
