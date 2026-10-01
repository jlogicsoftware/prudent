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

/// Why a goal has, or has not, a monthly contribution to suggest. CALCULATED, never stored. The
/// reason travels with the figure so a client never has to re-derive the rule (ADR-052): which of
/// these a goal is in follows a fixed order, the first that applies —
///   NOT_ACTIVE → REACHED → NO_TARGET_DATE → OVERDUE → CONTRIBUTION.
/// The zero value is UNSPECIFIED and is never produced, for the reason accounts.proto gives for
/// AccountType.
class GoalGuidance extends $pb.ProtobufEnum {
  static const GoalGuidance GOAL_GUIDANCE_UNSPECIFIED =
      GoalGuidance._(0, _omitEnumNames ? '' : 'GOAL_GUIDANCE_UNSPECIFIED');

  /// The goal is completed or archived: nothing is being saved towards it, so nothing is suggested.
  static const GoalGuidance GOAL_GUIDANCE_NOT_ACTIVE =
      GoalGuidance._(1, _omitEnumNames ? '' : 'GOAL_GUIDANCE_NOT_ACTIVE');

  /// An active goal whose envelope already holds the target. Nothing is left to save.
  static const GoalGuidance GOAL_GUIDANCE_REACHED =
      GoalGuidance._(2, _omitEnumNames ? '' : 'GOAL_GUIDANCE_REACHED');

  /// An active goal with money still to save and no date to save it by: open-ended, so there is no
  /// pace to suggest.
  static const GoalGuidance GOAL_GUIDANCE_NO_TARGET_DATE =
      GoalGuidance._(3, _omitEnumNames ? '' : 'GOAL_GUIDANCE_NO_TARGET_DATE');

  /// An active goal with money still to save whose target date is before the as-of date. Reported,
  /// not refused: a date that has slipped is the user's to move (PUT /api/v1/goals/{id}), and a
  /// contribution "to catch up by yesterday" would be a number with no meaning.
  static const GoalGuidance GOAL_GUIDANCE_OVERDUE =
      GoalGuidance._(4, _omitEnumNames ? '' : 'GOAL_GUIDANCE_OVERDUE');

  /// An active goal with money still to save and a target date that has not passed:
  /// monthly_contribution_minor and months_remaining are set.
  static const GoalGuidance GOAL_GUIDANCE_CONTRIBUTION =
      GoalGuidance._(5, _omitEnumNames ? '' : 'GOAL_GUIDANCE_CONTRIBUTION');

  static const $core.List<GoalGuidance> values = <GoalGuidance>[
    GOAL_GUIDANCE_UNSPECIFIED,
    GOAL_GUIDANCE_NOT_ACTIVE,
    GOAL_GUIDANCE_REACHED,
    GOAL_GUIDANCE_NO_TARGET_DATE,
    GOAL_GUIDANCE_OVERDUE,
    GOAL_GUIDANCE_CONTRIBUTION,
  ];

  static final $core.List<GoalGuidance?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static GoalGuidance? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GoalGuidance._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
