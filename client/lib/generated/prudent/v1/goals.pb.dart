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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'goals.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'goals.pbenum.dart';

/// A goal, as the server holds it.
class Goal extends $pb.GeneratedMessage {
  factory Goal({
    $core.String? id,
    $core.String? name,
    $core.String? currency,
    $fixnum.Int64? targetAmountMinor,
    $core.String? targetDate,
    GoalStatus? status,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? statusChangedAtMs,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (currency != null) result.currency = currency;
    if (targetAmountMinor != null) result.targetAmountMinor = targetAmountMinor;
    if (targetDate != null) result.targetDate = targetDate;
    if (status != null) result.status = status;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (statusChangedAtMs != null) result.statusChangedAtMs = statusChangedAtMs;
    return result;
  }

  Goal._();

  factory Goal.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Goal.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Goal',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aInt64(4, _omitFieldNames ? '' : 'targetAmountMinor')
    ..aOS(5, _omitFieldNames ? '' : 'targetDate')
    ..aE<GoalStatus>(6, _omitFieldNames ? '' : 'status',
        enumValues: GoalStatus.values)
    ..aInt64(7, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'statusChangedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Goal clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Goal copyWith(void Function(Goal) updates) =>
      super.copyWith((message) => updates(message as Goal)) as Goal;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Goal create() => Goal._();
  @$core.override
  Goal createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Goal getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Goal>(create);
  static Goal? _defaultInstance;

  /// Server-minted UUID. A create request carries no id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// What the user is saving for. Non-blank; not unique.
  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  /// ISO-4217. A goal is in ONE currency and is never converted (ADR-009); it is chosen at creation
  /// and cannot change afterwards, because money set aside for it is held in that currency.
  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  /// Minor units, POSITIVE: the amount to reach. Zero and negative are rejected. Zero is refused
  /// rather than stored because proto3 decodes an omitted field to 0, so it would make "the client
  /// forgot the target" indistinguishable from "a goal of nothing".
  @$pb.TagNumber(4)
  $fixnum.Int64 get targetAmountMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set targetAmountMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetAmountMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetAmountMinor() => $_clearField(4);

  /// The day the user wants to have reached it by, ISO-8601 YYYY-MM-DD. A civil date, for the
  /// reason records.proto gives for Record.date. Optional: a goal without one is open-ended. Not
  /// required to be in the future — whether a date is still reachable is progress guidance
  /// (jlogicsoftware/prudent#66), not a reason to refuse it here.
  @$pb.TagNumber(5)
  $core.String get targetDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set targetDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTargetDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearTargetDate() => $_clearField(5);

  @$pb.TagNumber(6)
  GoalStatus get status => $_getN(5);
  @$pb.TagNumber(6)
  set status(GoalStatus value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => $_clearField(6);

  /// Milliseconds since the Unix epoch.
  @$pb.TagNumber(7)
  $fixnum.Int64 get createdAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedAtMs() => $_clearField(7);

  /// When status last changed. Equal to created_at_ms until the first transition. Editing the
  /// goal's name, target or date does not move it.
  @$pb.TagNumber(8)
  $fixnum.Int64 get statusChangedAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set statusChangedAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasStatusChangedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearStatusChangedAtMs() => $_clearField(8);
}

/// POST /api/v1/goals — creates an ACTIVE goal.
class CreateGoalRequest extends $pb.GeneratedMessage {
  factory CreateGoalRequest({
    $core.String? name,
    $core.String? currency,
    $fixnum.Int64? targetAmountMinor,
    $core.String? targetDate,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (currency != null) result.currency = currency;
    if (targetAmountMinor != null) result.targetAmountMinor = targetAmountMinor;
    if (targetDate != null) result.targetDate = targetDate;
    return result;
  }

  CreateGoalRequest._();

  factory CreateGoalRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateGoalRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateGoalRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'currency')
    ..aInt64(3, _omitFieldNames ? '' : 'targetAmountMinor')
    ..aOS(4, _omitFieldNames ? '' : 'targetDate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGoalRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGoalRequest copyWith(void Function(CreateGoalRequest) updates) =>
      super.copyWith((message) => updates(message as CreateGoalRequest))
          as CreateGoalRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateGoalRequest create() => CreateGoalRequest._();
  @$core.override
  CreateGoalRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateGoalRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateGoalRequest>(create);
  static CreateGoalRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currency => $_getSZ(1);
  @$pb.TagNumber(2)
  set currency($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => $_clearField(2);

  /// See Goal.target_amount_minor.
  @$pb.TagNumber(3)
  $fixnum.Int64 get targetAmountMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set targetAmountMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTargetAmountMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearTargetAmountMinor() => $_clearField(3);

  /// See Goal.target_date. Absent means no date.
  @$pb.TagNumber(4)
  $core.String get targetDate => $_getSZ(3);
  @$pb.TagNumber(4)
  set targetDate($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetDate() => $_clearField(4);
}

/// PUT /api/v1/goals/{id} — a FULL REPLACEMENT of the mutable fields, for the presence reason set
/// out in categories.proto: an absent target_date CLEARS it. The currency is not here because it
/// cannot change, and the status is not here because only the lifecycle routes change it. Refused
/// (409) for an archived goal.
class UpdateGoalRequest extends $pb.GeneratedMessage {
  factory UpdateGoalRequest({
    $core.String? name,
    $fixnum.Int64? targetAmountMinor,
    $core.String? targetDate,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (targetAmountMinor != null) result.targetAmountMinor = targetAmountMinor;
    if (targetDate != null) result.targetDate = targetDate;
    return result;
  }

  UpdateGoalRequest._();

  factory UpdateGoalRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateGoalRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateGoalRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aInt64(2, _omitFieldNames ? '' : 'targetAmountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'targetDate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGoalRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGoalRequest copyWith(void Function(UpdateGoalRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateGoalRequest))
          as UpdateGoalRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateGoalRequest create() => UpdateGoalRequest._();
  @$core.override
  UpdateGoalRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateGoalRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateGoalRequest>(create);
  static UpdateGoalRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get targetAmountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set targetAmountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTargetAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearTargetAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get targetDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set targetDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTargetDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearTargetDate() => $_clearField(3);
}

/// GET /api/v1/goals — the caller's goals, optionally narrowed by the `status` query parameter
/// (ACTIVE, COMPLETED or ARCHIVED). Ordered by creation time, then id, so the order is total.
/// Unpaginated in v1 for the reason records.proto gives for ListRecordsResponse.
class ListGoalsResponse extends $pb.GeneratedMessage {
  factory ListGoalsResponse({
    $core.Iterable<Goal>? goals,
  }) {
    final result = create();
    if (goals != null) result.goals.addAll(goals);
    return result;
  }

  ListGoalsResponse._();

  factory ListGoalsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListGoalsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListGoalsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<Goal>(1, _omitFieldNames ? '' : 'goals', subBuilder: Goal.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalsResponse copyWith(void Function(ListGoalsResponse) updates) =>
      super.copyWith((message) => updates(message as ListGoalsResponse))
          as ListGoalsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListGoalsResponse create() => ListGoalsResponse._();
  @$core.override
  ListGoalsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListGoalsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListGoalsResponse>(create);
  static ListGoalsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Goal> get goals => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
