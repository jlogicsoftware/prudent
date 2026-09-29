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

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
