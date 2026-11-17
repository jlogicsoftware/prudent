import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../civil_date.dart';
import '../java_text.dart';
import '../refusal.dart';

part 'java_zone_ids.dart';

/// The IANA zones a plan may name, and the calendar day it is in one (rules 6.31, 6.42, ADR-037).
///
/// **The zone decides which day is today for a plan** — and so when an occurrence is due, overdue or
/// within its reminder's lead — and moves no occurrence date, which is a civil date. A Warsaw bill
/// due on the 1st does not turn overdue at one o'clock in the morning because some other zone's day
/// ended.
///
/// **Which ids are accepted is the server's list, not this database's.** `RecurrenceRule.parseZone`
/// takes exactly the ids in `ZoneId.getAvailableZoneIds()` — region ids and the legacy aliases such
/// as `US/Pacific`, never a fixed offset, which does not follow daylight saving. That list is
/// [_javaZoneIds], generated from the JVM; this class resolves the day from the `timezone` package's
/// database, and `plan_zones_test.dart` proves every accepted id resolves there and that the two
/// databases name the same day at the midnights of a set of zones whose rules are stable, the
/// millisecond before and the millisecond after (`test/golden/plans.json`).
///
/// **The two databases are two versions of the tz data.** The JDK's moves with its patch level
/// (Temurin 25.0.3 and 25.0.5 disagree about Moldova's 2026 rules), `package:timezone`'s with the
/// package. A zone legislated since the older of them is read at the older rules: a plan in it may
/// turn overdue an hour early or late on the changed days, until the package catches up. That is
/// why no per-zone offsets are committed as golden vectors — they would fail on every JDK build with
/// newer data than the one they were written on, and say nothing about the server's behaviour.
///
/// **The database stops at 2037**, the end of the transitions `package:timezone` ships: a zone that
/// observes daylight saving is read at its last offset afterwards. A plan's "today" is always near
/// the present, so this only matters for a device clock set past 2037.
abstract final class PlanZones {
  static bool _loaded = false;

  /// The JDK's own `SystemV/*` ids, which the tz database does not have, each read as the zone that
  /// follows the same rules today (a fixed `Etc/GMT±n`, or the region whose daylight-saving rules
  /// the id names). `test/golden/plans.json` proves the day agrees at each one's midnights.
  static const Map<String, String> _systemV = {
    'SystemV/AST4': 'Etc/GMT+4',
    'SystemV/AST4ADT': 'America/Halifax',
    'SystemV/CST6': 'Etc/GMT+6',
    'SystemV/CST6CDT': 'America/Chicago',
    'SystemV/EST5': 'Etc/GMT+5',
    'SystemV/EST5EDT': 'America/New_York',
    'SystemV/HST10': 'Etc/GMT+10',
    'SystemV/MST7': 'Etc/GMT+7',
    'SystemV/MST7MDT': 'America/Denver',
    'SystemV/PST8': 'Etc/GMT+8',
    'SystemV/PST8PDT': 'America/Los_Angeles',
    'SystemV/YST9': 'Etc/GMT+9',
    'SystemV/YST9YDT': 'America/Anchorage',
  };

  /// Whether [id] is a zone a plan may name: the server's own list, case-sensitive and exact.
  static bool isValid(String id) => _javaZoneIds.contains(id) && !unsupported.contains(id);

  /// Zones the server accepts and Prudent Local refuses, because the time-zone database it reads the
  /// day from cannot give their offsets as the JDK does: a day computed from a wrong offset is a plan
  /// that turns overdue at the wrong hour, and refusing is the honest answer (ADR-119).
  ///
  /// - `Africa/Casablanca` and `Africa/El_Aaiun`: Morocco's clock follows Ramadan, which the
  ///   database does not carry past 2026.
  /// - the JDK's own `SystemV/*DT` ids: daylight saving by the pre-2007 US rules, which no zone in the
  ///   database follows.
  ///
  /// This is a decision, not a snapshot of one JDK build: it does not move when a JDK ships newer
  /// tzdata. Zones whose rules merely changed in a newer tzdata than `package:timezone`'s are not
  /// here and are as old as the package's data is (see the class comment).
  static const Set<String> unsupported = {
    'Africa/Casablanca',
    'Africa/El_Aaiun',
    'SystemV/AST4ADT',
    'SystemV/CST6CDT',
    'SystemV/EST5EDT',
    'SystemV/MST7MDT',
    'SystemV/PST8PDT',
    'SystemV/YST9YDT',
  };

  /// The offset from UTC, in seconds, that [zoneId] has at [epochMs].
  static int offsetSecondsAt(String zoneId, int epochMs) {
    _load();
    return _location(zoneId).timeZone(epochMs).offset.inSeconds;
  }

  static void _load() {
    if (_loaded) return;
    tzdata.initializeTimeZones();
    _loaded = true;
  }

  static tz.Location _location(String zoneId) {
    try {
      return tz.getLocation(_systemV[zoneId] ?? zoneId);
    } on tz.LocationNotFoundException {
      throw StateError('The time-zone database has no zone "$zoneId".');
    }
  }

  /// `RecurrenceRule.parseZone`: [id] when it is a zone a plan may name, else a 400 (rule 6.31).
  static String parse(String? id) {
    if (id == null || javaIsBlank(id)) {
      throw const Refusal.invalid(
        '6.31',
        'A plan needs an explicit IANA time zone, e.g. Europe/Warsaw.',
      );
    }
    if (!isValid(id)) {
      throw const Refusal.invalid(
        '6.31',
        'Not an IANA time zone such as Europe/Warsaw. Fixed offsets are not accepted: they do not '
            'follow daylight saving.',
      );
    }
    return id;
  }

  /// `LocalDate.ofInstant(instant, zone)`: the calendar day it is in [zoneId] at [instant].
  ///
  /// [zoneId] must be one [parse] accepted. An id the database cannot resolve is a [StateError], not
  /// a guess: a day computed in the wrong zone is a plan that turns overdue at the wrong hour.
  static CivilDate dayAt(String zoneId, DateTime instant) {
    final ms = instant.millisecondsSinceEpoch;
    final local = DateTime.fromMillisecondsSinceEpoch(
      ms + offsetSecondsAt(zoneId, ms) * 1000,
      isUtc: true,
    );
    return CivilDate.fromEpochDay(
      DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/ 86400000,
    );
  }
}
