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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'goal_allocations.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'goal_allocations.pbenum.dart';

/// One entry of the history, as the server holds it. Immutable once written.
class GoalAllocation extends $pb.GeneratedMessage {
  factory GoalAllocation({
    $core.String? id,
    GoalAllocationKind? kind,
    $core.String? sourceGoalId,
    $core.String? targetGoalId,
    $core.String? currency,
    $fixnum.Int64? amountMinor,
    $core.String? note,
    $fixnum.Int64? createdAtMs,
    $core.String? createdBy,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (kind != null) result.kind = kind;
    if (sourceGoalId != null) result.sourceGoalId = sourceGoalId;
    if (targetGoalId != null) result.targetGoalId = targetGoalId;
    if (currency != null) result.currency = currency;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (note != null) result.note = note;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (createdBy != null) result.createdBy = createdBy;
    return result;
  }

  GoalAllocation._();

  factory GoalAllocation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GoalAllocation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GoalAllocation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<GoalAllocationKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: GoalAllocationKind.values)
    ..aOS(3, _omitFieldNames ? '' : 'sourceGoalId')
    ..aOS(4, _omitFieldNames ? '' : 'targetGoalId')
    ..aOS(5, _omitFieldNames ? '' : 'currency')
    ..aInt64(6, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(7, _omitFieldNames ? '' : 'note')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAtMs')
    ..aOS(9, _omitFieldNames ? '' : 'createdBy')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GoalAllocation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GoalAllocation copyWith(void Function(GoalAllocation) updates) =>
      super.copyWith((message) => updates(message as GoalAllocation))
          as GoalAllocation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GoalAllocation create() => GoalAllocation._();
  @$core.override
  GoalAllocation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GoalAllocation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GoalAllocation>(create);
  static GoalAllocation? _defaultInstance;

  /// Server-minted UUID. A create request carries no id.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  GoalAllocationKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(GoalAllocationKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// The goal money left. Present for WITHDRAW and MOVE, absent for ALLOCATE.
  @$pb.TagNumber(3)
  $core.String get sourceGoalId => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceGoalId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceGoalId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceGoalId() => $_clearField(3);

  /// The goal money entered. Present for ALLOCATE and MOVE, absent for WITHDRAW.
  @$pb.TagNumber(4)
  $core.String get targetGoalId => $_getSZ(3);
  @$pb.TagNumber(4)
  set targetGoalId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetGoalId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetGoalId() => $_clearField(4);

  /// ISO-4217: the currency of every goal the entry names. Never converted.
  @$pb.TagNumber(5)
  $core.String get currency => $_getSZ(4);
  @$pb.TagNumber(5)
  set currency($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => $_clearField(5);

  /// Minor units, POSITIVE: how much moved. The direction is the kind, not the sign, so a zero or
  /// negative amount is rejected rather than read as the opposite action. Zero is refused for the
  /// reason goals.proto gives for Goal.target_amount_minor.
  @$pb.TagNumber(6)
  $fixnum.Int64 get amountMinor => $_getI64(5);
  @$pb.TagNumber(6)
  set amountMinor($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAmountMinor() => $_has(5);
  @$pb.TagNumber(6)
  void clearAmountMinor() => $_clearField(6);

  /// Free text the user attached, at most 500 characters. Empty when none was given.
  @$pb.TagNumber(7)
  $core.String get note => $_getSZ(6);
  @$pb.TagNumber(7)
  set note($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNote() => $_has(6);
  @$pb.TagNumber(7)
  void clearNote() => $_clearField(7);

  /// Milliseconds since the Unix epoch, set by the server.
  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => $_clearField(8);

  /// The authenticated caller who wrote the entry (the user id today, because only the owner can
  /// write here). Recorded so the history stays truthful if a second kind of writer ever exists.
  @$pb.TagNumber(9)
  $core.String get createdBy => $_getSZ(8);
  @$pb.TagNumber(9)
  set createdBy($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCreatedBy() => $_has(8);
  @$pb.TagNumber(9)
  void clearCreatedBy() => $_clearField(9);
}

/// POST /api/v1/goal-allocations — records one entry. Which goal ids are required follows the kind
/// (see GoalAllocationKind); a field the kind does not use must be absent, and the request is
/// refused (400) if it is present, so a client that mixed up two actions finds out.
///
/// Refused (404) for a goal that is not the caller's, (409) when an entry would take an envelope
/// below zero or touch a goal whose state does not allow it: ALLOCATE and the target of a MOVE need
/// an ACTIVE goal; WITHDRAW and the source of a MOVE need an ACTIVE or COMPLETED one; an ARCHIVED
/// goal is read-only. An ALLOCATE is also refused (409) when it is more than the currency's free
/// money (CurrencyFreeMoney); a WITHDRAW or a MOVE never changes the total allocated in a currency,
/// so neither is limited by it.
class CreateGoalAllocationRequest extends $pb.GeneratedMessage {
  factory CreateGoalAllocationRequest({
    GoalAllocationKind? kind,
    $core.String? sourceGoalId,
    $core.String? targetGoalId,
    $fixnum.Int64? amountMinor,
    $core.String? note,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (sourceGoalId != null) result.sourceGoalId = sourceGoalId;
    if (targetGoalId != null) result.targetGoalId = targetGoalId;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (note != null) result.note = note;
    return result;
  }

  CreateGoalAllocationRequest._();

  factory CreateGoalAllocationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateGoalAllocationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateGoalAllocationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aE<GoalAllocationKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: GoalAllocationKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'sourceGoalId')
    ..aOS(3, _omitFieldNames ? '' : 'targetGoalId')
    ..aInt64(4, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(5, _omitFieldNames ? '' : 'note')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGoalAllocationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateGoalAllocationRequest copyWith(
          void Function(CreateGoalAllocationRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateGoalAllocationRequest))
          as CreateGoalAllocationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateGoalAllocationRequest create() =>
      CreateGoalAllocationRequest._();
  @$core.override
  CreateGoalAllocationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateGoalAllocationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateGoalAllocationRequest>(create);
  static CreateGoalAllocationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  GoalAllocationKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(GoalAllocationKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceGoalId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceGoalId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceGoalId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceGoalId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get targetGoalId => $_getSZ(2);
  @$pb.TagNumber(3)
  set targetGoalId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTargetGoalId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTargetGoalId() => $_clearField(3);

  /// See GoalAllocation.amount_minor.
  @$pb.TagNumber(4)
  $fixnum.Int64 get amountMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set amountMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAmountMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearAmountMinor() => $_clearField(4);

  /// See GoalAllocation.note. Optional.
  @$pb.TagNumber(5)
  $core.String get note => $_getSZ(4);
  @$pb.TagNumber(5)
  set note($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNote() => $_has(4);
  @$pb.TagNumber(5)
  void clearNote() => $_clearField(5);
}

/// GET /api/v1/goal-allocations — the caller's history, optionally narrowed by the `goalId` query
/// parameter to the entries that put money into or took it out of that goal. Newest first, then by
/// id, so the order is total. Unpaginated in v1 for the reason records.proto gives for
/// ListRecordsResponse.
class ListGoalAllocationsResponse extends $pb.GeneratedMessage {
  factory ListGoalAllocationsResponse({
    $core.Iterable<GoalAllocation>? allocations,
  }) {
    final result = create();
    if (allocations != null) result.allocations.addAll(allocations);
    return result;
  }

  ListGoalAllocationsResponse._();

  factory ListGoalAllocationsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListGoalAllocationsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListGoalAllocationsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<GoalAllocation>(1, _omitFieldNames ? '' : 'allocations',
        subBuilder: GoalAllocation.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalAllocationsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalAllocationsResponse copyWith(
          void Function(ListGoalAllocationsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListGoalAllocationsResponse))
          as ListGoalAllocationsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListGoalAllocationsResponse create() =>
      ListGoalAllocationsResponse._();
  @$core.override
  ListGoalAllocationsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListGoalAllocationsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListGoalAllocationsResponse>(create);
  static ListGoalAllocationsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<GoalAllocation> get allocations => $_getList(0);
}

/// What one goal's envelope holds right now. CALCULATED from the history on every read, never
/// stored, so it cannot disagree with the entries behind it.
class GoalEnvelope extends $pb.GeneratedMessage {
  factory GoalEnvelope({
    $core.String? goalId,
    $core.String? currency,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (goalId != null) result.goalId = goalId;
    if (currency != null) result.currency = currency;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  GoalEnvelope._();

  factory GoalEnvelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GoalEnvelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GoalEnvelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'goalId')
    ..aOS(2, _omitFieldNames ? '' : 'currency')
    ..aInt64(3, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GoalEnvelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GoalEnvelope copyWith(void Function(GoalEnvelope) updates) =>
      super.copyWith((message) => updates(message as GoalEnvelope))
          as GoalEnvelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GoalEnvelope create() => GoalEnvelope._();
  @$core.override
  GoalEnvelope createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GoalEnvelope getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GoalEnvelope>(create);
  static GoalEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get goalId => $_getSZ(0);
  @$pb.TagNumber(1)
  set goalId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasGoalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearGoalId() => $_clearField(1);

  /// The goal's currency.
  @$pb.TagNumber(2)
  $core.String get currency => $_getSZ(1);
  @$pb.TagNumber(2)
  set currency($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => $_clearField(2);

  /// Minor units, never negative: entries that put money in less entries that took it out.
  @$pb.TagNumber(3)
  $fixnum.Int64 get amountMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set amountMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmountMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmountMinor() => $_clearField(3);
}

/// GET /api/v1/goal-allocations/envelopes — one envelope per goal the caller has, in the goals'
/// creation order, a goal with no entries included at zero. Completed and archived goals are
/// listed too: an envelope is not hidden by the goal's state.
class ListGoalEnvelopesResponse extends $pb.GeneratedMessage {
  factory ListGoalEnvelopesResponse({
    $core.Iterable<GoalEnvelope>? envelopes,
  }) {
    final result = create();
    if (envelopes != null) result.envelopes.addAll(envelopes);
    return result;
  }

  ListGoalEnvelopesResponse._();

  factory ListGoalEnvelopesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListGoalEnvelopesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListGoalEnvelopesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<GoalEnvelope>(1, _omitFieldNames ? '' : 'envelopes',
        subBuilder: GoalEnvelope.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalEnvelopesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListGoalEnvelopesResponse copyWith(
          void Function(ListGoalEnvelopesResponse) updates) =>
      super.copyWith((message) => updates(message as ListGoalEnvelopesResponse))
          as ListGoalEnvelopesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListGoalEnvelopesResponse create() => ListGoalEnvelopesResponse._();
  @$core.override
  ListGoalEnvelopesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListGoalEnvelopesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListGoalEnvelopesResponse>(create);
  static ListGoalEnvelopesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<GoalEnvelope> get envelopes => $_getList(0);
}

/// One currency's money for goals, CALCULATED on every read and never stored (M4,
/// jlogicsoftware/prudent#65, docs/DECISIONS.md ADR-051). Per currency, never blended: there is no
/// FX, so a position in one currency says nothing about another (ADR-009).
///
///   eligible  the current balances, in this currency, of the accounts that are active and marked
///             eligible_for_goals (accounts.proto) — the same derived balance an Account carries.
///   allocated what the goals' envelopes hold in this currency, whatever the goals' states: money
///             in a completed goal is still set aside until it is withdrawn.
///   free      eligible less allocated: what a new ALLOCATE may draw on.
///
/// FREE MAY BE NEGATIVE. Spending a record, or taking an account out of the eligible set, lowers
/// eligible money after an allocation was made, and the allocation is history that is not
/// rewritten. A negative free says the envelopes hold more than the eligible accounts do; it
/// refuses every further ALLOCATE until the user withdraws or the balances recover.
class CurrencyFreeMoney extends $pb.GeneratedMessage {
  factory CurrencyFreeMoney({
    $core.String? currency,
    $fixnum.Int64? eligibleMinor,
    $fixnum.Int64? allocatedMinor,
    $fixnum.Int64? freeMinor,
    $core.Iterable<$core.String>? eligibleAccountIds,
  }) {
    final result = create();
    if (currency != null) result.currency = currency;
    if (eligibleMinor != null) result.eligibleMinor = eligibleMinor;
    if (allocatedMinor != null) result.allocatedMinor = allocatedMinor;
    if (freeMinor != null) result.freeMinor = freeMinor;
    if (eligibleAccountIds != null)
      result.eligibleAccountIds.addAll(eligibleAccountIds);
    return result;
  }

  CurrencyFreeMoney._();

  factory CurrencyFreeMoney.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CurrencyFreeMoney.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CurrencyFreeMoney',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'currency')
    ..aInt64(2, _omitFieldNames ? '' : 'eligibleMinor')
    ..aInt64(3, _omitFieldNames ? '' : 'allocatedMinor')
    ..aInt64(4, _omitFieldNames ? '' : 'freeMinor')
    ..pPS(5, _omitFieldNames ? '' : 'eligibleAccountIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrencyFreeMoney clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrencyFreeMoney copyWith(void Function(CurrencyFreeMoney) updates) =>
      super.copyWith((message) => updates(message as CurrencyFreeMoney))
          as CurrencyFreeMoney;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrencyFreeMoney create() => CurrencyFreeMoney._();
  @$core.override
  CurrencyFreeMoney createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CurrencyFreeMoney getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CurrencyFreeMoney>(create);
  static CurrencyFreeMoney? _defaultInstance;

  /// ISO-4217.
  @$pb.TagNumber(1)
  $core.String get currency => $_getSZ(0);
  @$pb.TagNumber(1)
  set currency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrency() => $_clearField(1);

  /// Minor units; negative when eligible accounts are overdrawn.
  @$pb.TagNumber(2)
  $fixnum.Int64 get eligibleMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set eligibleMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEligibleMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearEligibleMinor() => $_clearField(2);

  /// Minor units, never negative.
  @$pb.TagNumber(3)
  $fixnum.Int64 get allocatedMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set allocatedMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAllocatedMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAllocatedMinor() => $_clearField(3);

  /// eligible_minor less allocated_minor, in minor units; negative when over-allocated.
  @$pb.TagNumber(4)
  $fixnum.Int64 get freeMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set freeMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFreeMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearFreeMinor() => $_clearField(4);

  /// The accounts that make up eligible_minor: active, eligible_for_goals and holding this
  /// currency, in the accounts' name order. Empty when only goals name the currency.
  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get eligibleAccountIds => $_getList(4);
}

/// GET /api/v1/goal-allocations/free-money — one entry per currency that an eligible account holds
/// or a goal is set in, in currency-code order. A currency nothing names is absent: a client never
/// has to guess what absence means, because with no eligible account and no goal there is nothing
/// to report.
class GetFreeMoneyResponse extends $pb.GeneratedMessage {
  factory GetFreeMoneyResponse({
    $core.Iterable<CurrencyFreeMoney>? currencies,
  }) {
    final result = create();
    if (currencies != null) result.currencies.addAll(currencies);
    return result;
  }

  GetFreeMoneyResponse._();

  factory GetFreeMoneyResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GetFreeMoneyResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFreeMoneyResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<CurrencyFreeMoney>(1, _omitFieldNames ? '' : 'currencies',
        subBuilder: CurrencyFreeMoney.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFreeMoneyResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFreeMoneyResponse copyWith(void Function(GetFreeMoneyResponse) updates) =>
      super.copyWith((message) => updates(message as GetFreeMoneyResponse))
          as GetFreeMoneyResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GetFreeMoneyResponse create() => GetFreeMoneyResponse._();
  @$core.override
  GetFreeMoneyResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GetFreeMoneyResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetFreeMoneyResponse>(create);
  static GetFreeMoneyResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<CurrencyFreeMoney> get currencies => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
