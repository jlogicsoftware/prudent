import 'refusal.dart';

/// A civil date with no time and no zone — Java's `LocalDate`, as the server parses and prints it
/// (rule 3.4: ISO-8601 `YYYY-MM-DD`).
///
/// Dart's `DateTime.parse` is the wrong tool and is not used: it accepts `2026-02-30` and rolls it
/// into March, accepts a time and a zone, and carries a time zone into every comparison. The
/// server's `LocalDate.parse` refuses an impossible date, and a record filed on a rolled date is a
/// wrong total in the month it lands in.
///
/// [parse] reproduces `DateTimeFormatter.ISO_LOCAL_DATE` in strict mode: a year of 4 digits, or of
/// 5 to 10 digits with a `+`, or of 4 to 10 digits with a `-` (but never `-0000`, a negative zero),
/// within ±999 999 999; then `-MM-DD`, two ASCII digits each with no sign; then a day that exists
/// in that month of the proleptic Gregorian calendar. `test/golden/dates.json` holds it to the JVM.
final class CivilDate implements Comparable<CivilDate> {
  CivilDate._(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  /// The server's `RecordWriter.parseDate` (and `TransferResource`, `CorrectionResource`,
  /// `RecurrenceRule`, `GoalResource`, which all call `LocalDate.parse`): the date, or a 400.
  static CivilDate parse(String? text) {
    final date = tryParse(text);
    if (date == null) {
      throw const Refusal.invalid('3.4', 'Not an ISO-8601 date. Expected YYYY-MM-DD.');
    }
    return date;
  }

  /// [parse], answering `null` instead of a refusal.
  static CivilDate? tryParse(String? text) {
    if (text == null) return null;
    final year = _IsoYear.read(text);
    if (year == null) return null;
    var position = year.end;
    if (text.length != position + 6 ||
        text.codeUnitAt(position) != 0x2D ||
        text.codeUnitAt(position + 3) != 0x2D) {
      return null;
    }
    final month = _twoDigits(text, position + 1);
    final day = _twoDigits(text, position + 4);
    if (month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year.value, month)) return null;
    return CivilDate._(year.value, month, day);
  }

  /// The number of days in [month] of [year], proleptic Gregorian (Java's `IsoChronology`).
  static int daysInMonth(int year, int month) => switch (month) {
    2 => isLeapYear(year) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  /// Java's `IsoChronology.isLeapYear`.
  static bool isLeapYear(int year) => (year & 3) == 0 && (year % 100 != 0 || year % 400 == 0);

  // ── Calendar arithmetic (plans, ADR-037) ──────────────────────────────────────────────────────
  //
  // `LocalDate.plusDays`, `plusWeeks`, `plusMonths` and `plusYears`, which `RecurrenceRule.occurrence`
  // computes every occurrence with — always from the anchor, never from the previous one, so that
  // 31 January clamps to 28 February and returns to 31 March. All four refuse a result outside
  // Java's range of years (±999 999 999) with [CalendarOverflow], as `DateTimeException`.

  static const int _daysPerCycle = 146097;
  static const int _daysFromYear0To1970 = 719528;
  static const int _minYear = -999999999;
  static const int _maxYear = 999999999;

  /// `LocalDate.toEpochDay`: days since 1970-01-01.
  int get epochDay {
    final y = year;
    final m = month;
    var total = 365 * y;
    if (y >= 0) {
      total += (y + 3) ~/ 4 - (y + 99) ~/ 100 + (y + 399) ~/ 400;
    } else {
      total -= y ~/ -4 - y ~/ -100 + y ~/ -400;
    }
    total += (367 * m - 362) ~/ 12;
    total += day - 1;
    if (m > 2) {
      total--;
      if (!isLeapYear(year)) total--;
    }
    return total - _daysFromYear0To1970;
  }

  /// `LocalDate.ofEpochDay`.
  static CivilDate fromEpochDay(int epochDay) {
    var zeroDay = epochDay + _daysFromYear0To1970 - 60;
    var adjust = 0;
    if (zeroDay < 0) {
      final adjustCycles = (zeroDay + 1) ~/ _daysPerCycle - 1;
      adjust = adjustCycles * 400;
      zeroDay += -adjustCycles * _daysPerCycle;
    }
    int doyOf(int yearEst) =>
        zeroDay - (365 * yearEst + yearEst ~/ 4 - yearEst ~/ 100 + yearEst ~/ 400);
    var yearEst = (400 * zeroDay + 591) ~/ _daysPerCycle;
    var doyEst = doyOf(yearEst);
    if (doyEst < 0) {
      yearEst--;
      doyEst = doyOf(yearEst);
    }
    yearEst += adjust;
    final marchMonth0 = (doyEst * 5 + 2) ~/ 153;
    final month = (marchMonth0 + 2) % 12 + 1;
    final dom = doyEst - (marchMonth0 * 306 + 5) ~/ 10 + 1;
    yearEst += marchMonth0 ~/ 10;
    return CivilDate._checked(yearEst, month, dom);
  }

  static CivilDate _checked(int year, int month, int day) {
    if (year < _minYear || year > _maxYear) throw const CalendarOverflow();
    return CivilDate._(year, month, day);
  }

  /// `LocalDate.plusDays`.
  CivilDate plusDays(int days) => days == 0 ? this : fromEpochDay(epochDay + days);

  /// `LocalDate.plusWeeks`.
  CivilDate plusWeeks(int weeks) => plusDays(weeks * 7);

  /// `LocalDate.plusMonths`: the day of the month is clamped to the last day of a shorter month.
  CivilDate plusMonths(int months) {
    if (months == 0) return this;
    final calc = year * 12 + (month - 1) + months;
    final newYear = _floorDiv(calc, 12);
    final newMonth = calc - newYear * 12 + 1;
    return _previousValid(newYear, newMonth, day);
  }

  /// `LocalDate.plusYears`: 29 February falls on 28 February in a common year.
  CivilDate plusYears(int years) => years == 0 ? this : _previousValid(year + years, month, day);

  static int _floorDiv(int a, int b) {
    final q = a ~/ b;
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
  }

  static CivilDate _previousValid(int year, int month, int day) {
    if (year < _minYear || year > _maxYear) throw const CalendarOverflow();
    final last = daysInMonth(year, month);
    return CivilDate._(year, month, day > last ? last : day);
  }

  /// `LocalDate.toString()`: a 4-digit year padded with zeros, `+` before a year above 9999, `-`
  /// before a negative one.
  @override
  String toString() => '${formatIsoYear(year)}-${_pad2(month)}-${_pad2(day)}';

  @override
  int compareTo(CivilDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CivilDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// A date computation left the range `LocalDate` can hold (years ±999 999 999): Java's
/// `DateTimeException`. A rule that can answer "there is no later date" catches it; none else does.
final class CalendarOverflow implements Exception {
  const CalendarOverflow();

  @override
  String toString() => 'CalendarOverflow: outside the years -999999999 to 999999999';
}

/// A calendar month — Java's `YearMonth`, as the server's `BudgetResource.parseMonth` reads it
/// (rule 3.5): strictly `YYYY-MM` with four ASCII digits of year, stored as its first day.
final class CivilMonth implements Comparable<CivilMonth> {
  CivilMonth._(this.year, this.month);

  final int year;
  final int month;

  static final RegExp _shape = RegExp(r'^[0-9]{4}-[0-9]{2}$');

  /// `BudgetResource.parseMonth`: the month, or a 400. A signed or five-digit year is refused
  /// although `YearMonth.parse` alone would take it: here it is a typo, not a month.
  static CivilMonth parse(String? text) {
    final month = tryParse(text);
    if (month == null) {
      throw const Refusal.invalid('3.5', 'Not a month. Expected YYYY-MM.');
    }
    return month;
  }

  /// [parse], answering `null` instead of a refusal.
  static CivilMonth? tryParse(String? text) {
    if (text == null || !_shape.hasMatch(text)) return null;
    final year = int.parse(text.substring(0, 4));
    final month = int.parse(text.substring(5, 7));
    if (month < 1 || month > 12) return null;
    return CivilMonth._(year, month);
  }

  /// `YearMonth.atDay(1)`: how a month is stored (`budgets.sql`, `carry_over_resets.sql`).
  CivilDate get firstDay => CivilDate._(year, month, 1);

  @override
  String toString() => '${formatIsoYear(year)}-${_pad2(month)}';

  @override
  int compareTo(CivilMonth other) =>
      year != other.year ? year.compareTo(other.year) : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is CivilMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// A year as `LocalDate` and `YearMonth` print it.
String formatIsoYear(int year) {
  final digits = year.abs().toString().padLeft(4, '0');
  if (year < 0) return '-$digits';
  return year > 9999 ? '+$digits' : digits;
}

String _pad2(int value) => value.toString().padLeft(2, '0');

int? _twoDigits(String text, int at) {
  final high = _digit(text.codeUnitAt(at));
  final low = _digit(text.codeUnitAt(at + 1));
  return high == null || low == null ? null : high * 10 + low;
}

/// An ASCII digit's value; Java's `DecimalStyle.STANDARD` reads no other digit.
int? _digit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39 ? codeUnit - 0x30 : null;

/// The year field of `ISO_LOCAL_DATE`: `appendValue(YEAR, 4, 10, SignStyle.EXCEEDS_PAD)`, strict.
final class _IsoYear {
  _IsoYear(this.value, this.end);

  final int value;
  final int end;

  static const _minWidth = 4;
  static const _maxWidth = 10;
  static const _maxYear = 999999999;

  static _IsoYear? read(String text) {
    if (text.isEmpty) return null;
    var position = 0;
    final sign = text.codeUnitAt(0);
    final positive = sign == 0x2B;
    final negative = sign == 0x2D;
    if (positive || negative) position++;
    final start = position;
    var value = 0;
    while (position < text.length && position - start < _maxWidth) {
      final digit = _digit(text.codeUnitAt(position));
      if (digit == null) break;
      value = value * 10 + digit;
      position++;
    }
    final width = position - start;
    if (width < _minWidth) return null;
    if (negative) {
      // Strict parsing refuses a negative zero: "-0000" names no year.
      if (value == 0) return null;
      value = -value;
    } else if (positive ? width <= _minWidth : width > _minWidth) {
      // EXCEEDS_PAD: a '+' only when the year needs more than four digits, and then always.
      return null;
    }
    if (value > _maxYear || value < -_maxYear) return null;
    return _IsoYear(value, position);
  }
}
