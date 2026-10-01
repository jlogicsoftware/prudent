// This is a generated file - do not edit.
//
// Generated from prudent/v1/goal_allocations.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// What an entry did. The zero value is UNSPECIFIED and is never stored, for the reason
/// accounts.proto gives for AccountType.
class GoalAllocationKind extends $pb.ProtobufEnum {
  static const GoalAllocationKind GOAL_ALLOCATION_KIND_UNSPECIFIED =
      GoalAllocationKind._(
          0, _omitEnumNames ? '' : 'GOAL_ALLOCATION_KIND_UNSPECIFIED');

  /// Money set aside for a goal: increases the target's envelope.
  static const GoalAllocationKind GOAL_ALLOCATION_KIND_ALLOCATE =
      GoalAllocationKind._(
          1, _omitEnumNames ? '' : 'GOAL_ALLOCATION_KIND_ALLOCATE');

  /// Money released from a goal: decreases the source's envelope.
  static const GoalAllocationKind GOAL_ALLOCATION_KIND_WITHDRAW =
      GoalAllocationKind._(
          2, _omitEnumNames ? '' : 'GOAL_ALLOCATION_KIND_WITHDRAW');

  /// Money reassigned from one goal to another in the same currency: decreases the source's
  /// envelope and increases the target's by the same amount, as one entry.
  static const GoalAllocationKind GOAL_ALLOCATION_KIND_MOVE =
      GoalAllocationKind._(
          3, _omitEnumNames ? '' : 'GOAL_ALLOCATION_KIND_MOVE');

  static const $core.List<GoalAllocationKind> values = <GoalAllocationKind>[
    GOAL_ALLOCATION_KIND_UNSPECIFIED,
    GOAL_ALLOCATION_KIND_ALLOCATE,
    GOAL_ALLOCATION_KIND_WITHDRAW,
    GOAL_ALLOCATION_KIND_MOVE,
  ];

  static final $core.List<GoalAllocationKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static GoalAllocationKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GoalAllocationKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
