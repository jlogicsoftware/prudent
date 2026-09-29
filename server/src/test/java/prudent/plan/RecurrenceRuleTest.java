package prudent.plan;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.error.PrudentException;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.RecurrenceFrequency;

/**
 * The recurrence arithmetic and its validation (M2, jlogicsoftware/prudent#34), as a plain unit
 * test: a rule is a value, so none of this needs a database or a running application.
 */
class RecurrenceRuleTest {

  private static final ZoneId WARSAW = ZoneId.of("Europe/Warsaw");

  private static LocalDate d(String iso) {
    return LocalDate.parse(iso);
  }

  private static RecurrenceRule rule(
      Frequency frequency, int interval, String start, String until, Integer count) {
    return new RecurrenceRule(
        frequency, interval, d(start), WARSAW, until == null ? null : d(until), count);
  }

  private static List<LocalDate> dates(String... isos) {
    return Arrays.stream(isos).map(LocalDate::parse).toList();
  }

  // --- The five frequencies ------------------------------------------------------------------

  @Test
  void once_hasExactlyOneOccurrence() {
    RecurrenceRule once = rule(Frequency.ONCE, 1, "2026-10-15", null, null);
    assertEquals(dates("2026-10-15"), once.occurrencesBetween(d("2026-01-01"), d("2030-12-31")));
    assertEquals(List.of(), once.occurrencesBetween(d("2026-10-16"), d("2030-12-31")));
  }

  @Test
  void daily_withAnInterval() {
    RecurrenceRule everyThirdDay = rule(Frequency.DAILY, 3, "2026-10-01", null, null);
    assertEquals(
        dates("2026-10-01", "2026-10-04", "2026-10-07", "2026-10-10"),
        everyThirdDay.occurrencesBetween(d("2026-10-01"), d("2026-10-12")));
  }

  @Test
  void weekly_fortnightlyKeepsTheStartWeekday() {
    RecurrenceRule fortnightly = rule(Frequency.WEEKLY, 2, "2026-10-02", null, null);
    List<LocalDate> got = fortnightly.occurrencesBetween(d("2026-10-01"), d("2026-11-30"));
    assertEquals(
        dates("2026-10-02", "2026-10-16", "2026-10-30", "2026-11-13", "2026-11-27"), got);
    got.forEach(date -> assertEquals(d("2026-10-02").getDayOfWeek(), date.getDayOfWeek()));
  }

  @Test
  void monthly_clampsToMonthEndAndRestoresTheAnchorAfterwards() {
    // THE reason every occurrence is computed from the anchor: stepping from 28 February would pin
    // the rest of the year to the 28th.
    RecurrenceRule monthEnd = rule(Frequency.MONTHLY, 1, "2026-01-31", null, null);
    assertEquals(
        dates("2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"),
        monthEnd.occurrencesBetween(d("2026-01-01"), d("2026-05-31")));
  }

  @Test
  void monthly_clampsToTheLeapDayInALeapYear() {
    RecurrenceRule monthEnd = rule(Frequency.MONTHLY, 1, "2028-01-31", null, null);
    assertEquals(
        dates("2028-02-29"), monthEnd.occurrencesBetween(d("2028-02-01"), d("2028-02-29")));
  }

  @Test
  void monthly_quarterly() {
    RecurrenceRule quarterly = rule(Frequency.MONTHLY, 3, "2026-01-15", null, null);
    assertEquals(
        dates("2026-01-15", "2026-04-15", "2026-07-15", "2026-10-15"),
        quarterly.occurrencesBetween(d("2026-01-01"), d("2026-12-31")));
  }

  @Test
  void yearly_leapDayFallsOnTheTwentyEighthInACommonYear() {
    RecurrenceRule leap = rule(Frequency.YEARLY, 1, "2028-02-29", null, null);
    assertEquals(
        dates("2028-02-29", "2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"),
        leap.occurrencesBetween(d("2028-01-01"), d("2032-12-31")));
  }

  // --- End conditions ------------------------------------------------------------------------

  @Test
  void untilDate_isInclusive() {
    RecurrenceRule weekly = rule(Frequency.WEEKLY, 1, "2026-10-01", "2026-10-15", null);
    assertEquals(
        dates("2026-10-01", "2026-10-08", "2026-10-15"),
        weekly.occurrencesBetween(d("2026-01-01"), d("2027-12-31")));
  }

  @Test
  void occurrenceCount_countsTheFirstOccurrence() {
    RecurrenceRule threeTimes = rule(Frequency.MONTHLY, 1, "2026-10-10", null, 3);
    assertEquals(
        dates("2026-10-10", "2026-11-10", "2026-12-10"),
        threeTimes.occurrencesBetween(d("2026-01-01"), d("2030-12-31")));
  }

  @Test
  void occurrenceCount_holdsWhenTheWindowStartsLate() {
    // The count is by index from the anchor, not by what a window happens to see: a window starting
    // after the second occurrence sees only the third.
    RecurrenceRule threeTimes = rule(Frequency.MONTHLY, 1, "2026-10-10", null, 3);
    assertEquals(
        dates("2026-12-10"), threeTimes.occurrencesBetween(d("2026-11-11"), d("2030-12-31")));
  }

  @Test
  void noEnd_isBoundedOnlyByTheWindow() {
    RecurrenceRule daily = rule(Frequency.DAILY, 1, "2000-01-01", null, null);
    List<LocalDate> got = daily.occurrencesBetween(d("2026-10-01"), d("2026-10-03"));
    assertEquals(dates("2026-10-01", "2026-10-02", "2026-10-03"), got);
  }

  @Test
  void aWindowEntirelyBeforeTheStart_isEmpty() {
    RecurrenceRule monthly = rule(Frequency.MONTHLY, 1, "2026-10-10", null, null);
    assertEquals(List.of(), monthly.occurrencesBetween(d("2026-01-01"), d("2026-10-09")));
  }

  @Test
  void theSameWindowAlwaysYieldsTheSameDates() {
    RecurrenceRule monthEnd = rule(Frequency.MONTHLY, 2, "2026-01-31", null, 12);
    assertEquals(
        monthEnd.occurrencesBetween(d("2026-03-01"), d("2027-12-31")),
        monthEnd.occurrencesBetween(d("2026-03-01"), d("2027-12-31")));
  }

  @Test
  void aLateWindowAgreesWithTheSameSliceOfAnEarlyOne() {
    // The skip-ahead must never skip an occurrence: a window starting mid-schedule sees exactly the
    // dates a window from the anchor sees over the same span.
    for (Frequency frequency : List.of(Frequency.DAILY, Frequency.WEEKLY, Frequency.MONTHLY,
        Frequency.YEARLY)) {
      for (int interval : new int[] {1, 2, 3, 7}) {
        RecurrenceRule r = rule(frequency, interval, "2024-01-31", null, null);
        LocalDate from = d("2031-03-30");
        LocalDate to = d("2033-06-01");
        List<LocalDate> fromAnchor =
            r.occurrencesBetween(d("2024-01-31"), to).stream()
                .filter(date -> !date.isBefore(from))
                .toList();
        assertEquals(fromAnchor, r.occurrencesBetween(from, to), frequency + " x" + interval);
      }
    }
  }

  // --- The time zone -------------------------------------------------------------------------

  @Test
  void today_isReckonedInThePlansZoneNotTheServers() {
    // 22:30 UTC on 30 September is already 1 October in Warsaw (UTC+2 in summer time).
    Instant lateEveningUtc = Instant.parse("2026-09-30T22:30:00Z");
    assertEquals(d("2026-10-01"), rule(Frequency.ONCE, 1, "2026-10-01", null, null)
        .today(lateEveningUtc));
    RecurrenceRule newYork = new RecurrenceRule(
        Frequency.ONCE, 1, d("2026-10-01"), ZoneId.of("America/New_York"), null, null);
    assertEquals(d("2026-09-30"), newYork.today(lateEveningUtc));
  }

  @Test
  void parseZone_acceptsAnIanaRegion() {
    assertEquals(WARSAW, RecurrenceRule.parseZone("Europe/Warsaw"));
    assertEquals(ZoneId.of("UTC"), RecurrenceRule.parseZone("UTC"));
  }

  @ParameterizedTest
  @ValueSource(strings = {"", " ", "+02:00", "Z", "GMT+2", "UTC+01:00", "Europe/Atlantis",
      "europe/warsaw"})
  void parseZone_refusesFixedOffsetsAndUnknownIds(String id) {
    assertThrows(PrudentException.class, () -> RecurrenceRule.parseZone(id));
  }

  // --- Validation ----------------------------------------------------------------------------

  @Test
  void refuses_bothEndConditions() {
    assertInvalid(() -> rule(Frequency.DAILY, 1, "2026-10-01", "2026-12-01", 5));
  }

  @Test
  void refuses_anEndBeforeTheStart() {
    assertInvalid(() -> rule(Frequency.DAILY, 1, "2026-10-01", "2026-09-30", null));
  }

  @Test
  void accepts_anEndOnTheStartDate() {
    assertEquals(
        dates("2026-10-01"),
        rule(Frequency.DAILY, 1, "2026-10-01", "2026-10-01", null)
            .occurrencesBetween(d("2026-01-01"), d("2026-12-31")));
  }

  @ParameterizedTest
  @ValueSource(ints = {0, -1, RecurrenceRule.MAX_INTERVAL + 1})
  void refuses_anIntervalOutOfRangeForARepeatingPlan(int interval) {
    assertInvalid(() -> rule(Frequency.WEEKLY, interval, "2026-10-01", null, null));
  }

  @ParameterizedTest
  @ValueSource(ints = {0, RecurrenceRule.MAX_OCCURRENCES + 1})
  void refuses_anOccurrenceCountOutOfRange(int count) {
    assertInvalid(() -> rule(Frequency.WEEKLY, 1, "2026-10-01", null, count));
  }

  @Test
  void refuses_aOneOffWithAnIntervalOrAnEnd() {
    assertInvalid(() -> rule(Frequency.ONCE, 2, "2026-10-01", null, null));
    assertInvalid(() -> rule(Frequency.ONCE, 1, "2026-10-01", "2026-10-02", null));
    assertInvalid(() -> rule(Frequency.ONCE, 1, "2026-10-01", null, 1));
  }

  @Test
  void refuses_aMissingFrequencyStartOrZone() {
    assertInvalid(() -> new RecurrenceRule(null, 1, d("2026-10-01"), WARSAW, null, null));
    assertInvalid(() -> new RecurrenceRule(Frequency.DAILY, 1, null, WARSAW, null, null));
    assertInvalid(() -> new RecurrenceRule(Frequency.DAILY, 1, d("2026-10-01"), null, null, null));
  }

  // --- From the wire -------------------------------------------------------------------------

  private static Recurrence.Builder wire() {
    return Recurrence.newBuilder()
        .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_MONTHLY)
        .setInterval(1)
        .setStartDate("2026-10-01")
        .setTimeZone("Europe/Warsaw");
  }

  @Test
  void fromProto_readsEveryField() {
    RecurrenceRule r = RecurrenceRule.fromProto(wire().setOccurrenceCount(6).build(), true);
    assertEquals(
        new RecurrenceRule(Frequency.MONTHLY, 1, d("2026-10-01"), WARSAW, null, 6), r);
    RecurrenceRule until = RecurrenceRule.fromProto(wire().setUntilDate("2027-03-01").build(), true);
    assertEquals(d("2027-03-01"), until.untilDate());
  }

  @Test
  void fromProto_aOneOffMayOmitTheInterval() {
    RecurrenceRule r = RecurrenceRule.fromProto(
        wire().setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE).clearInterval().build(),
        true);
    assertEquals(1, r.interval());
  }

  @Test
  void fromProto_aRepeatingPlanMayNotOmitTheInterval() {
    assertInvalid(() -> RecurrenceRule.fromProto(wire().clearInterval().build(), true));
  }

  @Test
  void fromProto_refusesTheZeroValueFrequency() {
    assertInvalid(() -> RecurrenceRule.fromProto(
        wire().setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_UNSPECIFIED).build(), true));
  }

  @Test
  void fromProto_refusesAnAbsentRecurrence() {
    assertInvalid(() -> RecurrenceRule.fromProto(Recurrence.getDefaultInstance(), false));
  }

  @Test
  void fromProto_refusesAnImpossibleDate() {
    assertInvalid(() -> RecurrenceRule.fromProto(wire().setStartDate("2026-02-30").build(), true));
  }

  @Test
  void fromProto_aUint32AboveIntMaxIsRefusedNotWrapped() {
    // 2^32 - 1 reads as -1 in a Java int; it must stay too large, not become a small valid value.
    assertInvalid(() -> RecurrenceRule.fromProto(wire().setInterval(-1).build(), true));
    assertInvalid(() -> RecurrenceRule.fromProto(wire().setOccurrenceCount(-1).build(), true));
  }

  private static void assertInvalid(Executable executable) {
    PrudentException refused = assertThrows(PrudentException.class, executable);
    assertEquals(PrudentException.INVALID, refused.code());
    assertFalse(refused.getMessage().isBlank());
  }
}
