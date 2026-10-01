// This is a generated file - do not edit.
//
// Generated from prudent/v1/goals.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Where a goal is in its life. The zero value is UNSPECIFIED and is never stored, for the reason
/// accounts.proto gives for AccountType: proto3 decodes an omitted field to 0, and whichever
/// constant sat there would make "the field is missing" indistinguishable from a real state.
class GoalStatus extends $pb.ProtobufEnum {
  static const GoalStatus GOAL_STATUS_UNSPECIFIED =
      GoalStatus._(0, _omitEnumNames ? '' : 'GOAL_STATUS_UNSPECIFIED');

  /// Being saved for. The state every goal is created in, and the only one that can be completed.
  static const GoalStatus GOAL_STATUS_ACTIVE =
      GoalStatus._(1, _omitEnumNames ? '' : 'GOAL_STATUS_ACTIVE');

  /// Reached. The goal and its history stay readable; it can be archived or reactivated.
  static const GoalStatus GOAL_STATUS_COMPLETED =
      GoalStatus._(2, _omitEnumNames ? '' : 'GOAL_STATUS_COMPLETED');

  /// No longer wanted. Kept, read-only: it cannot be edited until it is reactivated.
  static const GoalStatus GOAL_STATUS_ARCHIVED =
      GoalStatus._(3, _omitEnumNames ? '' : 'GOAL_STATUS_ARCHIVED');

  static const $core.List<GoalStatus> values = <GoalStatus>[
    GOAL_STATUS_UNSPECIFIED,
    GOAL_STATUS_ACTIVE,
    GOAL_STATUS_COMPLETED,
    GOAL_STATUS_ARCHIVED,
  ];

  static final $core.List<GoalStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static GoalStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GoalStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
