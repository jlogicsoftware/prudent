import '../civil_date.dart';
import '../java_text.dart';
import '../refusal.dart';
import 'plan_zones.dart';

/// How often a plan repeats (`prudent.plan.Frequency`).
enum PlanFrequency { once, daily, weekly, monthly, yearly }

/// When a plan's occurrences fall: a validated value and the one place the date arithmetic lives
/// (`RecurrenceRule.java`, rules 6.30, 6.31, 6.36, ADR-037).
///
/// **Every occurrence is a civil date.** The n-th one is computed *from [startDate]*, never by
/// stepping from the one before it: stepping would let 31 January clamp to 28 February and stay on
/// the 28th for good. From the anchor it is 31 January, 28 February, 31 March — the month-end the
/// person chose — and every occurrence is a pure function of the rule and its index, which is what
/// lets generation be repeated and still agree with itself.
///
/// **The time zone moves no date.** It decides which calendar day is today for this plan
/// ([today]), and so when an occurrence is due and when it is overdue.
///
/// Construction validates every invariant and refuses with a [Refusal] (400), so a rule that exists
/// is one the arithmetic can answer for.
final class RecurrenceRule {
  RecurrenceRule._(
    this.frequency,
    this.interval,
    this.startDate,
    this.timeZone,
    this.untilDate,
    this.occurrenceCount,
  );

  final PlanFrequency frequency;

  /// Every [interval] units of [frequency]; exactly 1 for a one-off.
  final int interval;

  /// The first occurrence and the anchor for every later one.
  final CivilDate startDate;

  /// The IANA zone in which "today" is reckoned for this plan.
  final String timeZone;

  /// The last date an occurrence may fall on, inclusive; or null.
  final CivilDate? untilDate;

  /// The total number of occurrences; or null.
  final int? occurrenceCount;

  /// The largest interval accepted: far beyond any real schedule, bounded so `index * interval`
  /// can never be the thing that overflows.
  static const int maxInterval = 1000;

  /// The largest occurrence count accepted: daily for over twenty-seven years.
  static const int maxOccurrences = 10000;

  /// `RecurrenceRule.fromProto` for a recurrence that is present: the rule, or a 400 naming what is
  /// wrong. [interval] and [occurrenceCount] are wire `uint32`s, so a value above 2^31 − 1 saturates
  /// and is refused with the rest rather than wrapping into a small valid one. [untilDate] and
  /// [occurrenceCount] are the wire's `end` oneof: at most one is set.
  factory RecurrenceRule.parse({
    required PlanFrequency? frequency,
    required int interval,
    required String startDate,
    required String timeZone,
    String? untilDate,
    int? occurrenceCount,
  }) {
    if (untilDate != null && occurrenceCount != null) {
      throw const Refusal.invalid(
        '6.30',
        'A plan can end on a date or after a number of occurrences, not both.',
      );
    }
    // The server reads the end date, the count, the start date and the zone before it validates the
    // rule as a whole; every one of those is a 400, so the order shows in the message only.
    final until = untilDate == null ? null : _parseDate(untilDate, 'until date');
    final start = _parseDate(startDate, 'start date');
    final zone = PlanZones.parse(timeZone);
    if (frequency == null) {
      throw const Refusal.invalid(
        '6.30',
        'A plan needs a recurrence frequency: once, daily, weekly, monthly or yearly.',
      );
    }
    // An omitted interval is 0 on the wire. For a one-off it does not apply, so 0 and 1 both mean
    // the one occurrence; for a repeating frequency 0 is refused rather than read as 1 — "the client
    // forgot" and "every period" must not become the same stored rule.
    final every = frequency == PlanFrequency.once && interval == 0 ? 1 : _saturated(interval);
    final count = occurrenceCount == null ? null : _saturated(occurrenceCount);
    if (frequency == PlanFrequency.once) {
      if (every != 1) {
        throw const Refusal.invalid('6.30', 'A one-off plan has no repeat interval.');
      }
      if (until != null || count != null) {
        throw const Refusal.invalid(
          '6.30',
          'A one-off plan has exactly one occurrence and takes no end condition.',
        );
      }
    } else if (every < 1 || every > maxInterval) {
      throw const Refusal.invalid(
        '6.30',
        'A repeating plan needs an interval from 1 to $maxInterval.',
      );
    }
    if (until != null && until.compareTo(start) < 0) {
      throw const Refusal.invalid('6.30', 'A plan cannot end before its start date.');
    }
    if (count != null && (count < 1 || count > maxOccurrences)) {
      throw const Refusal.invalid(
        '6.30',
        "A plan's occurrence count must be from 1 to $maxOccurrences.",
      );
    }
    return RecurrenceRule._(frequency, every, start, zone, until, count);
  }

  /// The [index]-th occurrence (0-based), computed from the anchor and ignoring the end condition,
  /// which [occurrencesBetween] applies. Throws [CalendarOverflow] beyond the last year a date can
  /// hold.
  CivilDate occurrence(int index) {
    if (index < 0) throw ArgumentError.value(index, 'index', 'is never negative');
    final step = index * interval;
    return switch (frequency) {
      PlanFrequency.once => startDate,
      PlanFrequency.daily => startDate.plusDays(step),
      PlanFrequency.weekly => startDate.plusWeeks(step),
      PlanFrequency.monthly => startDate.plusMonths(step),
      PlanFrequency.yearly => startDate.plusYears(step),
    };
  }

  bool _isWithinEnd(int index, CivilDate date) {
    if (frequency == PlanFrequency.once) return index == 0;
    if (occurrenceCount != null) return index < occurrenceCount!;
    return untilDate == null || date.compareTo(untilDate!) <= 0;
  }

  /// Every occurrence in `[from, to]`, inclusive, in date order. The window is what bounds a rule
  /// with no end; a caller never asks for "all of them".
  List<CivilDate> occurrencesBetween(CivilDate from, CivilDate to) {
    if (to.compareTo(from) < 0) {
      throw ArgumentError('Window ends ($to) before it starts ($from)');
    }
    final dates = <CivilDate>[];
    for (var index = _firstIndexNotAfter(from); ; index++) {
      final CivilDate date;
      try {
        date = occurrence(index);
      } on CalendarOverflow {
        // Beyond the last year a date can hold: there are no later occurrences for any window.
        break;
      }
      if (date.compareTo(to) > 0 || !_isWithinEnd(index, date)) break;
      if (date.compareTo(from) >= 0) dates.add(date);
    }
    return dates;
  }

  /// An index whose occurrence is on or before [from] — a safe place to start scanning, so a daily
  /// rule anchored years ago does not walk every day since. Conservative by one period for months
  /// and years, where clamping makes the exact index awkward to state; it never changes the answer.
  int _firstIndexNotAfter(CivilDate from) {
    if (frequency == PlanFrequency.once || from.compareTo(startDate) <= 0) return 0;
    final periods = switch (frequency) {
      PlanFrequency.daily => from.epochDay - startDate.epochDay,
      PlanFrequency.weekly => (from.epochDay - startDate.epochDay) ~/ 7,
      PlanFrequency.monthly =>
        (from.year * 12 + from.month) - (startDate.year * 12 + startDate.month) - 1,
      PlanFrequency.yearly => from.year - startDate.year - 1,
      PlanFrequency.once => 0,
    };
    final first = periods ~/ interval - 1;
    return first < 0 ? 0 : first;
  }

  /// The calendar day it is for this plan at [instant] — the one thing the time zone decides. An
  /// occurrence dated on or before it is due; one dated before it and still open is overdue.
  CivilDate today(DateTime instant) => PlanZones.dayAt(timeZone, instant);

  @override
  bool operator ==(Object other) =>
      other is RecurrenceRule &&
      other.frequency == frequency &&
      other.interval == interval &&
      other.startDate == startDate &&
      other.timeZone == timeZone &&
      other.untilDate == untilDate &&
      other.occurrenceCount == occurrenceCount;

  @override
  int get hashCode =>
      Object.hash(frequency, interval, startDate, timeZone, untilDate, occurrenceCount);

  @override
  String toString() =>
      '${frequency.name.toUpperCase()}|$interval|$startDate|$timeZone|${untilDate ?? ''}|'
      '${occurrenceCount ?? ''}';

  static CivilDate _parseDate(String text, String what) {
    if (javaIsBlank(text)) {
      throw Refusal.invalid('6.30', 'A plan needs a $what, as ISO-8601 YYYY-MM-DD.');
    }
    return CivilDate.tryParse(text) ??
        (throw Refusal.invalid('6.30', 'Not an ISO-8601 $what. Expected YYYY-MM-DD.'));
  }

  /// A wire uint32 read as a Java `int` is negative above 2^31 − 1: saturating keeps such a value
  /// too large, so the range checks refuse it.
  static int _saturated(int unsigned) => unsigned > 0x7fffffff ? 0x7fffffff : unsigned;
}
