// This is a generated file - do not edit.
//
// Generated from prudent_local/v1/store.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// The wire's AccountType, value for value (the mapper converts by name and a test proves every value).
class AccountKind extends $pb.ProtobufEnum {
  static const AccountKind ACCOUNT_KIND_UNSPECIFIED =
      AccountKind._(0, _omitEnumNames ? '' : 'ACCOUNT_KIND_UNSPECIFIED');
  static const AccountKind ACCOUNT_KIND_CASH =
      AccountKind._(1, _omitEnumNames ? '' : 'ACCOUNT_KIND_CASH');
  static const AccountKind ACCOUNT_KIND_CARD =
      AccountKind._(2, _omitEnumNames ? '' : 'ACCOUNT_KIND_CARD');
  static const AccountKind ACCOUNT_KIND_CHECKING =
      AccountKind._(3, _omitEnumNames ? '' : 'ACCOUNT_KIND_CHECKING');
  static const AccountKind ACCOUNT_KIND_SAVINGS =
      AccountKind._(4, _omitEnumNames ? '' : 'ACCOUNT_KIND_SAVINGS');

  static const $core.List<AccountKind> values = <AccountKind>[
    ACCOUNT_KIND_UNSPECIFIED,
    ACCOUNT_KIND_CASH,
    ACCOUNT_KIND_CARD,
    ACCOUNT_KIND_CHECKING,
    ACCOUNT_KIND_SAVINGS,
  ];

  static final $core.List<AccountKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static AccountKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AccountKind._(super.value, super.name);
}

class CategoryDirection extends $pb.ProtobufEnum {
  static const CategoryDirection CATEGORY_DIRECTION_UNSPECIFIED =
      CategoryDirection._(
          0, _omitEnumNames ? '' : 'CATEGORY_DIRECTION_UNSPECIFIED');
  static const CategoryDirection CATEGORY_DIRECTION_EXPENSE =
      CategoryDirection._(
          1, _omitEnumNames ? '' : 'CATEGORY_DIRECTION_EXPENSE');
  static const CategoryDirection CATEGORY_DIRECTION_INCOME =
      CategoryDirection._(2, _omitEnumNames ? '' : 'CATEGORY_DIRECTION_INCOME');

  static const $core.List<CategoryDirection> values = <CategoryDirection>[
    CATEGORY_DIRECTION_UNSPECIFIED,
    CATEGORY_DIRECTION_EXPENSE,
    CATEGORY_DIRECTION_INCOME,
  ];

  static final $core.List<CategoryDirection?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static CategoryDirection? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CategoryDirection._(super.value, super.name);
}

class GoalState extends $pb.ProtobufEnum {
  static const GoalState GOAL_STATE_UNSPECIFIED =
      GoalState._(0, _omitEnumNames ? '' : 'GOAL_STATE_UNSPECIFIED');
  static const GoalState GOAL_STATE_ACTIVE =
      GoalState._(1, _omitEnumNames ? '' : 'GOAL_STATE_ACTIVE');
  static const GoalState GOAL_STATE_COMPLETED =
      GoalState._(2, _omitEnumNames ? '' : 'GOAL_STATE_COMPLETED');
  static const GoalState GOAL_STATE_ARCHIVED =
      GoalState._(3, _omitEnumNames ? '' : 'GOAL_STATE_ARCHIVED');

  static const $core.List<GoalState> values = <GoalState>[
    GOAL_STATE_UNSPECIFIED,
    GOAL_STATE_ACTIVE,
    GOAL_STATE_COMPLETED,
    GOAL_STATE_ARCHIVED,
  ];

  static final $core.List<GoalState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static GoalState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const GoalState._(super.value, super.name);
}

class AllocationKind extends $pb.ProtobufEnum {
  static const AllocationKind ALLOCATION_KIND_UNSPECIFIED =
      AllocationKind._(0, _omitEnumNames ? '' : 'ALLOCATION_KIND_UNSPECIFIED');
  static const AllocationKind ALLOCATION_KIND_ALLOCATE =
      AllocationKind._(1, _omitEnumNames ? '' : 'ALLOCATION_KIND_ALLOCATE');
  static const AllocationKind ALLOCATION_KIND_WITHDRAW =
      AllocationKind._(2, _omitEnumNames ? '' : 'ALLOCATION_KIND_WITHDRAW');
  static const AllocationKind ALLOCATION_KIND_MOVE =
      AllocationKind._(3, _omitEnumNames ? '' : 'ALLOCATION_KIND_MOVE');

  static const $core.List<AllocationKind> values = <AllocationKind>[
    ALLOCATION_KIND_UNSPECIFIED,
    ALLOCATION_KIND_ALLOCATE,
    ALLOCATION_KIND_WITHDRAW,
    ALLOCATION_KIND_MOVE,
  ];

  static final $core.List<AllocationKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static AllocationKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AllocationKind._(super.value, super.name);
}

class Frequency extends $pb.ProtobufEnum {
  static const Frequency FREQUENCY_UNSPECIFIED =
      Frequency._(0, _omitEnumNames ? '' : 'FREQUENCY_UNSPECIFIED');
  static const Frequency FREQUENCY_ONCE =
      Frequency._(1, _omitEnumNames ? '' : 'FREQUENCY_ONCE');
  static const Frequency FREQUENCY_DAILY =
      Frequency._(2, _omitEnumNames ? '' : 'FREQUENCY_DAILY');
  static const Frequency FREQUENCY_WEEKLY =
      Frequency._(3, _omitEnumNames ? '' : 'FREQUENCY_WEEKLY');
  static const Frequency FREQUENCY_MONTHLY =
      Frequency._(4, _omitEnumNames ? '' : 'FREQUENCY_MONTHLY');
  static const Frequency FREQUENCY_YEARLY =
      Frequency._(5, _omitEnumNames ? '' : 'FREQUENCY_YEARLY');

  static const $core.List<Frequency> values = <Frequency>[
    FREQUENCY_UNSPECIFIED,
    FREQUENCY_ONCE,
    FREQUENCY_DAILY,
    FREQUENCY_WEEKLY,
    FREQUENCY_MONTHLY,
    FREQUENCY_YEARLY,
  ];

  static final $core.List<Frequency?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static Frequency? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Frequency._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
