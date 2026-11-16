import 'refusal.dart';

/// How `spend-by-period` buckets time (`AnalyticsResource.java`, phase-0 §0.3 row 7.2).
enum SpendGranularity { month, year }

/// A run of whole calendar months in which spending is counted: the one shape both analytics
/// questions reduce to. A month, a year and a trailing window of months or years are all whole
/// months, so a record's day never matters — only its year and month, which keeps the boundary
/// rule ("the first and last day of the month are in") from being a date comparison anyone can get
/// wrong by a day.
///
/// A month is held as `year * 12 + (month - 1)`, so a window is two integers and "next month" is
/// `+ 1` across a year end.
final class SpendWindow {
  const SpendWindow._(this._first, this._last);

  final int _first;
  final int _last;

  static int _index(int year, int month) => year * 12 + (month - 1);

  /// The largest year `java.time.LocalDate` holds. A year beyond it is not a date there; the server
  /// answers 500 (an unhandled `DateTimeException`). Local refuses with a 400 instead: a figure
  /// the server cannot compute is not one to reproduce (ADR-118).
  static const int maxYear = 999999999;

  /// `spend-by-category`'s `year` and optional `month`: the server's checks in its order — a year is
  /// required (400), a month is 1–12 (400). A year with no [month] is the whole year.
  static SpendWindow ofYearOrMonth({required int? year, required int? month}) {
    if (year == null) {
      throw const Refusal.invalid('7.1', 'spend-by-category needs a year.');
    }
    if (month != null && (month < 1 || month > 12)) {
      throw const Refusal.invalid('7.1', 'month must be 1-12.');
    }
    _checkYear(year);
    return month != null
        ? SpendWindow._(_index(year, month), _index(year, month))
        : SpendWindow._(_index(year, 1), _index(year, 12));
  }

  /// `GRANULARITY_MONTH` or `YEAR`, as the server reads the query parameter: `equalsIgnoreCase`
  /// against the two names (every letter of them is ASCII, and no non-ASCII character folds to
  /// one), anything else a 400.
  static SpendGranularity parseGranularity(String? text) {
    // Dart's toUpperCase folds a few non-ASCII letters to ASCII ones; Java's equalsIgnoreCase of
    // "MONTH" / "YEAR" would not match them, so the text itself must be ASCII.
    final ascii = text != null && text.codeUnits.every((unit) => unit < 0x80);
    return switch (ascii ? text.toUpperCase() : null) {
      'MONTH' => SpendGranularity.month,
      'YEAR' => SpendGranularity.year,
      _ => throw const Refusal.invalid('7.2', 'granularity must be MONTH or YEAR.'),
    };
  }

  /// `spend-by-period`'s `count`, 1–60 (400 otherwise), and the trailing window it names: [count]
  /// buckets ending with the one that holds [anchorYear]/[anchorMonth] — "the current period",
  /// which the server resolves in UTC once per request (ADR-014) and Local resolves from the clock
  /// it is given.
  static SpendWindow trailing({
    required SpendGranularity granularity,
    required int? count,
    required int anchorYear,
    required int anchorMonth,
  }) {
    if (count == null || count < 1 || count > 60) {
      throw const Refusal.invalid('7.2', 'count must be between 1 and 60.');
    }
    return switch (granularity) {
      SpendGranularity.month => SpendWindow._(
        _index(anchorYear, anchorMonth) - (count - 1),
        _index(anchorYear, anchorMonth),
      ),
      SpendGranularity.year => SpendWindow._(
        _index(anchorYear - (count - 1), 1),
        _index(anchorYear, 12),
      ),
    };
  }

  static void _checkYear(int year) {
    if (year < -maxYear || year > maxYear) {
      throw const Refusal.invalid('7.1', 'year is out of range.');
    }
  }

  /// Whether a date in [year]/[month] is inside the window.
  bool contains(int year, int month) {
    final index = _index(year, month);
    return index >= _first && index <= _last;
  }

  /// The period a date falls in, as `yyyy-MM` or `yyyy` — the keys the response sorts by. A year is
  /// four digits, zero-padded, as `DateTimeFormatter` prints one; the windows are the present's, so
  /// years before 1 and after 9999 are never labelled.
  static String label(SpendGranularity granularity, int year, int month) {
    final y = year.toString().padLeft(4, '0');
    return granularity == SpendGranularity.year ? y : '$y-${month.toString().padLeft(2, '0')}';
  }
}
