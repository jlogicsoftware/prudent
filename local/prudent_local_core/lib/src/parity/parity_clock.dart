import '../civil_date.dart';
import '../plans/plan_zones.dart';

/// The moment a parity scenario runs at, pinned once (finding F-07, ADR-119).
///
/// The server reads its own clock for everything a plan does — which day it is in a plan's zone, when
/// an occurrence is overdue, when a reminder is due — and its routes take no `asOf`. Local takes the
/// instant as an argument. So a scenario cannot name a date: a fixed one would be in the past or the
/// future of the server's real "today" depending on the day the suite runs. It names a date *relative
/// to today in a zone* instead, and both backends read the same one:
///
/// - `"@today(Europe/Warsaw)"` is today's date in that zone at [now], `"@today(Pacific/Kiritimati)+2"`
///   two days after it, `"@today(UTC)-1"` yesterday. [expand] replaces every such string in a step's
///   input before either backend sees it.
/// - the local backend reads [now] as its `asOf`; the server reads the wall clock a moment later.
///
/// Two backends reading one clock a few seconds apart disagree only if a zone's midnight passes
/// between them, and [crossedMidnight] says whether it did, so the engine runs the scenario again
/// rather than report a difference that is nobody's bug. A scenario can still pin the day boundary
/// *itself* without a pinned server: two zones 25 hours apart (`Pacific/Kiritimati`, UTC+14, and
/// `Pacific/Pago_Pago`, UTC−11) are never on the same date, so a date that is today in one is overdue
/// in the other at every instant.
final class ParityClock {
  /// A clock pinned at [now] (the wall clock when omitted), which re-reads [wall] to decide whether a
  /// zone's midnight has passed since.
  ParityClock({DateTime? now, DateTime Function()? wall})
    : now = (now ?? DateTime.now()).toUtc(),
      _wall = wall ?? DateTime.now;

  /// The instant every backend of the scenario treats as "now".
  final DateTime now;

  final DateTime Function() _wall;
  final Set<String> _zones = {};

  static final RegExp _token = RegExp(r'^@today\(([^)]+)\)([+-][0-9]+)?$');

  /// [value] with every `@today(zone)±n` string replaced by that civil date, through maps and lists.
  /// Any other value is returned as it is.
  Object? expand(Object? value) {
    if (value is String) {
      final match = _token.firstMatch(value);
      if (match == null) return value;
      final zone = match.group(1)!;
      if (!PlanZones.isValid(zone)) {
        throw FormatException('"$value" names "$zone", which is not a time zone a plan may use.');
      }
      _zones.add(zone);
      final offset = match.group(2) == null ? 0 : int.parse(match.group(2)!);
      return PlanZones.dayAt(zone, now).plusDays(offset).toString();
    }
    if (value is Map) {
      return {for (final MapEntry(:key, :value) in value.entries) key as String: expand(value)};
    }
    if (value is List) return [for (final item in value) expand(item)];
    return value;
  }

  /// The date it is in [zone] at [now].
  CivilDate today(String zone) => PlanZones.dayAt(zone, now);

  /// Whether, for any zone a scenario named, the calendar day now differs from the day at [now].
  bool get crossedMidnight {
    final later = _wall();
    return _zones.any((zone) => PlanZones.dayAt(zone, now) != PlanZones.dayAt(zone, later));
  }
}
