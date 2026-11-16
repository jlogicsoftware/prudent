// This is a generated file - do not edit.
//
// Generated from prudent/v1/plans.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// How often a plan repeats. The zero value is UNSPECIFIED and is REJECTED server-side, for the
/// reason accounts.proto gives for AccountType: proto3 decodes an omitted field to 0, and whichever
/// constant sits there would make "the client forgot" indistinguishable from a real answer. ONCE
/// is a real answer — a one-off plan — so it cannot be the zero value.
class RecurrenceFrequency extends $pb.ProtobufEnum {
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_UNSPECIFIED =
      RecurrenceFrequency._(
          0, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_UNSPECIFIED');

  /// Exactly one occurrence, on start_date. Takes no interval and no end condition.
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_ONCE =
      RecurrenceFrequency._(
          1, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_ONCE');
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_DAILY =
      RecurrenceFrequency._(
          2, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_DAILY');

  /// On start_date's weekday.
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_WEEKLY =
      RecurrenceFrequency._(
          3, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_WEEKLY');

  /// On start_date's day of the month, CLAMPED to the last day of a shorter month and restored
  /// afterwards: a plan anchored on 31 January falls on 28/29 February and then on 31 March again.
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_MONTHLY =
      RecurrenceFrequency._(
          4, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_MONTHLY');

  /// On start_date's month and day; a 29 February anchor falls on 28 February in a common year.
  static const RecurrenceFrequency RECURRENCE_FREQUENCY_YEARLY =
      RecurrenceFrequency._(
          5, _omitEnumNames ? '' : 'RECURRENCE_FREQUENCY_YEARLY');

  static const $core.List<RecurrenceFrequency> values = <RecurrenceFrequency>[
    RECURRENCE_FREQUENCY_UNSPECIFIED,
    RECURRENCE_FREQUENCY_ONCE,
    RECURRENCE_FREQUENCY_DAILY,
    RECURRENCE_FREQUENCY_WEEKLY,
    RECURRENCE_FREQUENCY_MONTHLY,
    RECURRENCE_FREQUENCY_YEARLY,
  ];

  static final $core.List<RecurrenceFrequency?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static RecurrenceFrequency? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RecurrenceFrequency._(super.value, super.name);
}

/// Where one planned occurrence stands (M2, jlogicsoftware/prudent#56). PLANNED, COMPLETED and
/// SKIPPED are what the server STORES; OVERDUE is never stored — it is a PLANNED occurrence whose
/// date is before today in its plan's time zone, worked out at read time. Storing it would need a
/// job to flip it at midnight in every user's zone, and a missed run would leave a stale row; a
/// derived value cannot be stale. The zero value is UNSPECIFIED, for the reason AccountType gives.
class OccurrenceStatus extends $pb.ProtobufEnum {
  static const OccurrenceStatus OCCURRENCE_STATUS_UNSPECIFIED =
      OccurrenceStatus._(
          0, _omitEnumNames ? '' : 'OCCURRENCE_STATUS_UNSPECIFIED');

  /// Expected, not yet resolved, and not yet past its date.
  static const OccurrenceStatus OCCURRENCE_STATUS_PLANNED =
      OccurrenceStatus._(1, _omitEnumNames ? '' : 'OCCURRENCE_STATUS_PLANNED');

  /// Confirmed into an actual Record (M2, jlogicsoftware/prudent#57) by
  /// POST /api/v1/occurrences/{id}/confirm, which is the only thing that sets it. Final: a
  /// completed occurrence cannot be skipped, restored or confirmed again.
  static const OccurrenceStatus OCCURRENCE_STATUS_COMPLETED =
      OccurrenceStatus._(
          2, _omitEnumNames ? '' : 'OCCURRENCE_STATUS_COMPLETED');

  /// The user decided it will not happen. It can be restored to PLANNED.
  static const OccurrenceStatus OCCURRENCE_STATUS_SKIPPED =
      OccurrenceStatus._(3, _omitEnumNames ? '' : 'OCCURRENCE_STATUS_SKIPPED');

  /// PLANNED, and its date has passed in the plan's time zone. Still open: it can be skipped, or
  /// confirmed.
  static const OccurrenceStatus OCCURRENCE_STATUS_OVERDUE =
      OccurrenceStatus._(4, _omitEnumNames ? '' : 'OCCURRENCE_STATUS_OVERDUE');

  static const $core.List<OccurrenceStatus> values = <OccurrenceStatus>[
    OCCURRENCE_STATUS_UNSPECIFIED,
    OCCURRENCE_STATUS_PLANNED,
    OCCURRENCE_STATUS_COMPLETED,
    OCCURRENCE_STATUS_SKIPPED,
    OCCURRENCE_STATUS_OVERDUE,
  ];

  static final $core.List<OccurrenceStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static OccurrenceStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const OccurrenceStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
