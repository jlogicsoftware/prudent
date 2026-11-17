import '../refusal.dart';

/// A plan's reminder lead time in whole calendar days: one of a closed set, anything else refused
/// and never rounded (rule 6.32, finding F-08, ADR-054).
///
/// The Java set `{0, 1, 2, 3, 7}` is the rule; the schema's `CHECK` allows 0–365 and is only the
/// wider net behind it. A client that asks for four days and is quietly given three would show the
/// person a setting that is not the one in force.
abstract final class ReminderLeadTimes {
  /// The lead times offered, in days: the day itself, one, two, three, and a week.
  static const List<int> supported = [0, 1, 2, 3, 7];

  /// The lead time a reminder starts with, and the one an absent value means.
  static const int defaultDays = 1;

  /// `ReminderSetting.fromProto`'s lead time: [leadDays] when it is [supported], [defaultDays] when
  /// absent, else a 400. [leadDays] is a wire `uint32`, so a value above 2^31 − 1 is refused with the
  /// rest, never wrapped into a supported-looking one.
  static int parse(int? leadDays) {
    final days = leadDays ?? defaultDays;
    if (!supported.contains(days)) {
      throw const Refusal.invalid(
        '6.32',
        "A reminder's lead time must be one of [0, 1, 2, 3, 7] days before the occurrence.",
      );
    }
    return days;
  }
}
