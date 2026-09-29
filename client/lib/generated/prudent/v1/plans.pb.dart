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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'plans.pbenum.dart';
import 'records.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'plans.pbenum.dart';

enum Recurrence_End { untilDate, occurrenceCount, notSet }

/// When and how often a plan's occurrences fall.
///
/// EVERY OCCURRENCE IS A CIVIL DATE (YYYY-MM-DD), for the reason records.proto gives for
/// Record.date: a bill is due on a calendar day, and an instant would shift a day at a DST
/// boundary. The n-th occurrence is always computed FROM start_date, never from the previous
/// occurrence — stepping month by month would let a February clamp drag every later date to the
/// 28th.
class Recurrence extends $pb.GeneratedMessage {
  factory Recurrence({
    RecurrenceFrequency? frequency,
    $core.int? interval,
    $core.String? startDate,
    $core.String? timeZone,
    $core.String? untilDate,
    $core.int? occurrenceCount,
  }) {
    final result = create();
    if (frequency != null) result.frequency = frequency;
    if (interval != null) result.interval = interval;
    if (startDate != null) result.startDate = startDate;
    if (timeZone != null) result.timeZone = timeZone;
    if (untilDate != null) result.untilDate = untilDate;
    if (occurrenceCount != null) result.occurrenceCount = occurrenceCount;
    return result;
  }

  Recurrence._();

  factory Recurrence.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Recurrence.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Recurrence_End> _Recurrence_EndByTag = {
    5: Recurrence_End.untilDate,
    6: Recurrence_End.occurrenceCount,
    0: Recurrence_End.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Recurrence',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..oo(0, [5, 6])
    ..aE<RecurrenceFrequency>(1, _omitFieldNames ? '' : 'frequency',
        enumValues: RecurrenceFrequency.values)
    ..aI(2, _omitFieldNames ? '' : 'interval', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'startDate')
    ..aOS(4, _omitFieldNames ? '' : 'timeZone')
    ..aOS(5, _omitFieldNames ? '' : 'untilDate')
    ..aI(6, _omitFieldNames ? '' : 'occurrenceCount',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recurrence clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Recurrence copyWith(void Function(Recurrence) updates) =>
      super.copyWith((message) => updates(message as Recurrence)) as Recurrence;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Recurrence create() => Recurrence._();
  @$core.override
  Recurrence createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Recurrence getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Recurrence>(create);
  static Recurrence? _defaultInstance;

  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  Recurrence_End whichEnd() => _Recurrence_EndByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearEnd() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  RecurrenceFrequency get frequency => $_getN(0);
  @$pb.TagNumber(1)
  set frequency(RecurrenceFrequency value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFrequency() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrequency() => $_clearField(1);

  /// CUSTOM INTERVALS: every `interval` units of `frequency` — 2 with WEEKLY is fortnightly, 3 with
  /// MONTHLY is quarterly. Required and 1..1000 for a repeating frequency; 0 (omitted) is REJECTED
  /// there rather than defaulted to 1, for the zero-value reason above. For ONCE it does not apply:
  /// omit it or send 1.
  @$pb.TagNumber(2)
  $core.int get interval => $_getIZ(1);
  @$pb.TagNumber(2)
  set interval($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInterval() => $_has(1);
  @$pb.TagNumber(2)
  void clearInterval() => $_clearField(2);

  /// The first occurrence, and the anchor every later one is computed from. ISO-8601 YYYY-MM-DD.
  @$pb.TagNumber(3)
  $core.String get startDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set startDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartDate() => $_clearField(3);

  /// An IANA time-zone id, e.g. "Europe/Warsaw". REQUIRED and EXPLICIT, never inferred from the
  /// server: it decides which calendar day is TODAY for this plan, and therefore when an occurrence
  /// becomes due and when it becomes overdue (jlogicsoftware/prudent#56). The server runs in UTC; a
  /// Warsaw user's plan due on the 1st must not turn overdue at 01:00 local time because the
  /// server's day ended. Fixed offsets such as "+02:00" are refused — they do not follow daylight
  /// saving, so they are wrong for half of every year in most of the places they would be used.
  @$pb.TagNumber(4)
  $core.String get timeZone => $_getSZ(3);
  @$pb.TagNumber(4)
  set timeZone($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimeZone() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimeZone() => $_clearField(4);

  /// The last date an occurrence may fall on, INCLUSIVE. Not before start_date.
  @$pb.TagNumber(5)
  $core.String get untilDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set untilDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUntilDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearUntilDate() => $_clearField(5);

  /// How many occurrences there are in total, counting the one on start_date. 1..10000.
  @$pb.TagNumber(6)
  $core.int get occurrenceCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set occurrenceCount($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOccurrenceCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearOccurrenceCount() => $_clearField(6);
}

/// A plan, as the server holds it.
class Plan extends $pb.GeneratedMessage {
  factory Plan({
    $core.String? id,
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? currency,
    $core.String? accountId,
    $core.String? categoryId,
    $core.String? payee,
    $core.String? note,
    Recurrence? recurrence,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (currency != null) result.currency = currency;
    if (accountId != null) result.accountId = accountId;
    if (categoryId != null) result.categoryId = categoryId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    if (recurrence != null) result.recurrence = recurrence;
    return result;
  }

  Plan._();

  factory Plan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Plan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Plan',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aInt64(3, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(4, _omitFieldNames ? '' : 'currency')
    ..aOS(5, _omitFieldNames ? '' : 'accountId')
    ..aOS(6, _omitFieldNames ? '' : 'categoryId')
    ..aOS(7, _omitFieldNames ? '' : 'payee')
    ..aOS(8, _omitFieldNames ? '' : 'note')
    ..aOM<Recurrence>(9, _omitFieldNames ? '' : 'recurrence',
        subBuilder: Recurrence.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Plan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Plan copyWith(void Function(Plan) updates) =>
      super.copyWith((message) => updates(message as Plan)) as Plan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Plan create() => Plan._();
  @$core.override
  Plan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Plan getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Plan>(create);
  static Plan? _defaultInstance;

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
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  /// Minor units, SIGNED exactly as Record.amount_minor is (ADR-014): negative is planned spending,
  /// positive is planned income, zero is rejected. The same sign convention means confirming an
  /// occurrence copies the amount rather than translating it.
  @$pb.TagNumber(3)
  $fixnum.Int64 get amountMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set amountMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmountMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmountMinor() => $_clearField(3);

  /// ISO-4217, and one the account below holds — the same refusal records.proto describes.
  @$pb.TagNumber(4)
  $core.String get currency => $_getSZ(3);
  @$pb.TagNumber(4)
  set currency($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrency() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrency() => $_clearField(4);

  /// The account the money is expected to move in. Required, and the caller's own.
  @$pb.TagNumber(5)
  $core.String get accountId => $_getSZ(4);
  @$pb.TagNumber(5)
  set accountId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAccountId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAccountId() => $_clearField(5);

  /// The spend/income category. Required, as it is on an ordinary record: a plan is expected
  /// income or spending, and a planned transfer is not part of this model.
  @$pb.TagNumber(6)
  $core.String get categoryId => $_getSZ(5);
  @$pb.TagNumber(6)
  set categoryId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCategoryId() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategoryId() => $_clearField(6);

  /// See Record.payee / Record.note. Optional.
  @$pb.TagNumber(7)
  $core.String get payee => $_getSZ(6);
  @$pb.TagNumber(7)
  set payee($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPayee() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayee() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get note => $_getSZ(7);
  @$pb.TagNumber(8)
  set note($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNote() => $_has(7);
  @$pb.TagNumber(8)
  void clearNote() => $_clearField(8);

  @$pb.TagNumber(9)
  Recurrence get recurrence => $_getN(8);
  @$pb.TagNumber(9)
  set recurrence(Recurrence value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasRecurrence() => $_has(8);
  @$pb.TagNumber(9)
  void clearRecurrence() => $_clearField(9);
  @$pb.TagNumber(9)
  Recurrence ensureRecurrence() => $_ensure(8);
}

/// POST /api/v1/plans
class CreatePlanRequest extends $pb.GeneratedMessage {
  factory CreatePlanRequest({
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? currency,
    $core.String? accountId,
    $core.String? categoryId,
    $core.String? payee,
    $core.String? note,
    Recurrence? recurrence,
  }) {
    final result = create();
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (currency != null) result.currency = currency;
    if (accountId != null) result.accountId = accountId;
    if (categoryId != null) result.categoryId = categoryId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    if (recurrence != null) result.recurrence = recurrence;
    return result;
  }

  CreatePlanRequest._();

  factory CreatePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreatePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreatePlanRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aOS(4, _omitFieldNames ? '' : 'accountId')
    ..aOS(5, _omitFieldNames ? '' : 'categoryId')
    ..aOS(6, _omitFieldNames ? '' : 'payee')
    ..aOS(7, _omitFieldNames ? '' : 'note')
    ..aOM<Recurrence>(8, _omitFieldNames ? '' : 'recurrence',
        subBuilder: Recurrence.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreatePlanRequest copyWith(void Function(CreatePlanRequest) updates) =>
      super.copyWith((message) => updates(message as CreatePlanRequest))
          as CreatePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreatePlanRequest create() => CreatePlanRequest._();
  @$core.override
  CreatePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreatePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreatePlanRequest>(create);
  static CreatePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  /// See Plan.amount_minor: negative is spending, positive is income, zero is rejected.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get accountId => $_getSZ(3);
  @$pb.TagNumber(4)
  set accountId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccountId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccountId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get categoryId => $_getSZ(4);
  @$pb.TagNumber(5)
  set categoryId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCategoryId() => $_has(4);
  @$pb.TagNumber(5)
  void clearCategoryId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get payee => $_getSZ(5);
  @$pb.TagNumber(6)
  set payee($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPayee() => $_has(5);
  @$pb.TagNumber(6)
  void clearPayee() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get note => $_getSZ(6);
  @$pb.TagNumber(7)
  set note($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNote() => $_has(6);
  @$pb.TagNumber(7)
  void clearNote() => $_clearField(7);

  /// Required.
  @$pb.TagNumber(8)
  Recurrence get recurrence => $_getN(7);
  @$pb.TagNumber(8)
  set recurrence(Recurrence value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasRecurrence() => $_has(7);
  @$pb.TagNumber(8)
  void clearRecurrence() => $_clearField(8);
  @$pb.TagNumber(8)
  Recurrence ensureRecurrence() => $_ensure(7);
}

/// PUT /api/v1/plans/{id} — a FULL REPLACEMENT, for the presence reason set out in
/// categories.proto. An absent payee or note clears it.
class UpdatePlanRequest extends $pb.GeneratedMessage {
  factory UpdatePlanRequest({
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? currency,
    $core.String? accountId,
    $core.String? categoryId,
    $core.String? payee,
    $core.String? note,
    Recurrence? recurrence,
  }) {
    final result = create();
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (currency != null) result.currency = currency;
    if (accountId != null) result.accountId = accountId;
    if (categoryId != null) result.categoryId = categoryId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    if (recurrence != null) result.recurrence = recurrence;
    return result;
  }

  UpdatePlanRequest._();

  factory UpdatePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdatePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdatePlanRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aOS(4, _omitFieldNames ? '' : 'accountId')
    ..aOS(5, _omitFieldNames ? '' : 'categoryId')
    ..aOS(6, _omitFieldNames ? '' : 'payee')
    ..aOS(7, _omitFieldNames ? '' : 'note')
    ..aOM<Recurrence>(8, _omitFieldNames ? '' : 'recurrence',
        subBuilder: Recurrence.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdatePlanRequest copyWith(void Function(UpdatePlanRequest) updates) =>
      super.copyWith((message) => updates(message as UpdatePlanRequest))
          as UpdatePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdatePlanRequest create() => UpdatePlanRequest._();
  @$core.override
  UpdatePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdatePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdatePlanRequest>(create);
  static UpdatePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get accountId => $_getSZ(3);
  @$pb.TagNumber(4)
  set accountId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccountId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccountId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get categoryId => $_getSZ(4);
  @$pb.TagNumber(5)
  set categoryId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCategoryId() => $_has(4);
  @$pb.TagNumber(5)
  void clearCategoryId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get payee => $_getSZ(5);
  @$pb.TagNumber(6)
  set payee($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPayee() => $_has(5);
  @$pb.TagNumber(6)
  void clearPayee() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get note => $_getSZ(6);
  @$pb.TagNumber(7)
  set note($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNote() => $_has(6);
  @$pb.TagNumber(7)
  void clearNote() => $_clearField(7);

  @$pb.TagNumber(8)
  Recurrence get recurrence => $_getN(7);
  @$pb.TagNumber(8)
  set recurrence(Recurrence value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasRecurrence() => $_has(7);
  @$pb.TagNumber(8)
  void clearRecurrence() => $_clearField(8);
  @$pb.TagNumber(8)
  Recurrence ensureRecurrence() => $_ensure(7);
}

/// GET /api/v1/plans — every plan owned by the authenticated user. Unpaginated in v1 for the reason
/// records.proto gives for ListRecordsResponse.
class ListPlansResponse extends $pb.GeneratedMessage {
  factory ListPlansResponse({
    $core.Iterable<Plan>? plans,
  }) {
    final result = create();
    if (plans != null) result.plans.addAll(plans);
    return result;
  }

  ListPlansResponse._();

  factory ListPlansResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListPlansResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListPlansResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<Plan>(1, _omitFieldNames ? '' : 'plans', subBuilder: Plan.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListPlansResponse copyWith(void Function(ListPlansResponse) updates) =>
      super.copyWith((message) => updates(message as ListPlansResponse))
          as ListPlansResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListPlansResponse create() => ListPlansResponse._();
  @$core.override
  ListPlansResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListPlansResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListPlansResponse>(create);
  static ListPlansResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Plan> get plans => $_getList(0);
}

/// One dated occurrence of a plan, with the plan's own fields alongside so a list can be drawn
/// without a second call per row. Like the plan it is NEVER a transaction: nothing here is read by
/// a balance or by analytics until it is confirmed into a Record.
class PlanOccurrence extends $pb.GeneratedMessage {
  factory PlanOccurrence({
    $core.String? id,
    $core.String? planId,
    $core.String? occurrenceDate,
    OccurrenceStatus? status,
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? currency,
    $core.String? accountId,
    $core.String? categoryId,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (planId != null) result.planId = planId;
    if (occurrenceDate != null) result.occurrenceDate = occurrenceDate;
    if (status != null) result.status = status;
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (currency != null) result.currency = currency;
    if (accountId != null) result.accountId = accountId;
    if (categoryId != null) result.categoryId = categoryId;
    return result;
  }

  PlanOccurrence._();

  factory PlanOccurrence.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlanOccurrence.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlanOccurrence',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'planId')
    ..aOS(3, _omitFieldNames ? '' : 'occurrenceDate')
    ..aE<OccurrenceStatus>(4, _omitFieldNames ? '' : 'status',
        enumValues: OccurrenceStatus.values)
    ..aOS(5, _omitFieldNames ? '' : 'title')
    ..aInt64(6, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(7, _omitFieldNames ? '' : 'currency')
    ..aOS(8, _omitFieldNames ? '' : 'accountId')
    ..aOS(9, _omitFieldNames ? '' : 'categoryId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanOccurrence clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanOccurrence copyWith(void Function(PlanOccurrence) updates) =>
      super.copyWith((message) => updates(message as PlanOccurrence))
          as PlanOccurrence;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlanOccurrence create() => PlanOccurrence._();
  @$core.override
  PlanOccurrence createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlanOccurrence getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlanOccurrence>(create);
  static PlanOccurrence? _defaultInstance;

  /// Server-minted UUID.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get planId => $_getSZ(1);
  @$pb.TagNumber(2)
  set planId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPlanId() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlanId() => $_clearField(2);

  /// The civil date this occurrence falls on, ISO-8601 YYYY-MM-DD.
  @$pb.TagNumber(3)
  $core.String get occurrenceDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set occurrenceDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOccurrenceDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearOccurrenceDate() => $_clearField(3);

  @$pb.TagNumber(4)
  OccurrenceStatus get status => $_getN(3);
  @$pb.TagNumber(4)
  set status(OccurrenceStatus value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStatus() => $_has(3);
  @$pb.TagNumber(4)
  void clearStatus() => $_clearField(4);

  /// The plan's fields as they are now. Per-occurrence edits (M2, jlogicsoftware/prudent#57) will
  /// override these on the occurrence itself; until then an occurrence is exactly its plan.
  @$pb.TagNumber(5)
  $core.String get title => $_getSZ(4);
  @$pb.TagNumber(5)
  set title($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTitle() => $_has(4);
  @$pb.TagNumber(5)
  void clearTitle() => $_clearField(5);

  /// Signed, as Plan.amount_minor.
  @$pb.TagNumber(6)
  $fixnum.Int64 get amountMinor => $_getI64(5);
  @$pb.TagNumber(6)
  set amountMinor($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAmountMinor() => $_has(5);
  @$pb.TagNumber(6)
  void clearAmountMinor() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get currency => $_getSZ(6);
  @$pb.TagNumber(7)
  set currency($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCurrency() => $_has(6);
  @$pb.TagNumber(7)
  void clearCurrency() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get accountId => $_getSZ(7);
  @$pb.TagNumber(8)
  set accountId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAccountId() => $_has(7);
  @$pb.TagNumber(8)
  void clearAccountId() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get categoryId => $_getSZ(8);
  @$pb.TagNumber(9)
  set categoryId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCategoryId() => $_has(8);
  @$pb.TagNumber(9)
  void clearCategoryId() => $_clearField(9);
}

/// GET /api/v1/occurrences/upcoming and GET /api/v1/occurrences/overdue. Both are ordered by date
/// ascending, then id, so the order is total. Unpaginated in v1 for the reason records.proto gives
/// for ListRecordsResponse — both are bounded by their windows.
class ListOccurrencesResponse extends $pb.GeneratedMessage {
  factory ListOccurrencesResponse({
    $core.Iterable<PlanOccurrence>? occurrences,
  }) {
    final result = create();
    if (occurrences != null) result.occurrences.addAll(occurrences);
    return result;
  }

  ListOccurrencesResponse._();

  factory ListOccurrencesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListOccurrencesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListOccurrencesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<PlanOccurrence>(1, _omitFieldNames ? '' : 'occurrences',
        subBuilder: PlanOccurrence.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOccurrencesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListOccurrencesResponse copyWith(
          void Function(ListOccurrencesResponse) updates) =>
      super.copyWith((message) => updates(message as ListOccurrencesResponse))
          as ListOccurrencesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListOccurrencesResponse create() => ListOccurrencesResponse._();
  @$core.override
  ListOccurrencesResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListOccurrencesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListOccurrencesResponse>(create);
  static ListOccurrencesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PlanOccurrence> get occurrences => $_getList(0);
}

/// POST /api/v1/occurrences/{id}/confirm (M2, jlogicsoftware/prudent#57) — the user says this
/// occurrence happened, and the server writes the actual transaction. Every field is OPTIONAL and an
/// absent one takes the occurrence's own value (its date, and its plan's amount, account and
/// category), so "yes, exactly as planned" is the empty message `{}` — the request must still carry
/// a body, as on every POST that declares one.
/// What is sent replaces that value for THIS transaction only; the plan and its other occurrences
/// are unchanged.
///
/// Presence is explicit (`optional`) rather than zero-means-absent, for the reason categories.proto
/// gives: an amount of 0 is a mistake to be REFUSED, not a request for the default.
///
/// Deliberately not editable here: the currency (it is the plan's, and the account must hold it),
/// and the title, payee and note (copied from the plan; edit the record afterwards).
class ConfirmOccurrenceRequest extends $pb.GeneratedMessage {
  factory ConfirmOccurrenceRequest({
    $core.String? date,
    $fixnum.Int64? amountMinor,
    $core.String? accountId,
    $core.String? categoryId,
  }) {
    final result = create();
    if (date != null) result.date = date;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (accountId != null) result.accountId = accountId;
    if (categoryId != null) result.categoryId = categoryId;
    return result;
  }

  ConfirmOccurrenceRequest._();

  factory ConfirmOccurrenceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfirmOccurrenceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmOccurrenceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'date')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'accountId')
    ..aOS(4, _omitFieldNames ? '' : 'categoryId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmOccurrenceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmOccurrenceRequest copyWith(
          void Function(ConfirmOccurrenceRequest) updates) =>
      super.copyWith((message) => updates(message as ConfirmOccurrenceRequest))
          as ConfirmOccurrenceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmOccurrenceRequest create() => ConfirmOccurrenceRequest._();
  @$core.override
  ConfirmOccurrenceRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfirmOccurrenceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmOccurrenceRequest>(create);
  static ConfirmOccurrenceRequest? _defaultInstance;

  /// The civil date the money actually moved, ISO-8601 YYYY-MM-DD. Defaults to the occurrence date.
  /// Any date is accepted, not only ones near the occurrence: a bill paid a week late, or a month
  /// early, is confirmed on the day it was paid.
  @$pb.TagNumber(1)
  $core.String get date => $_getSZ(0);
  @$pb.TagNumber(1)
  set date($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDate() => $_has(0);
  @$pb.TagNumber(1)
  void clearDate() => $_clearField(1);

  /// Signed minor units, as Record.amount_minor. Defaults to the plan's amount. Nonzero.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);

  /// Defaults to the plan's account. Must be the caller's and must hold the plan's currency.
  @$pb.TagNumber(3)
  $core.String get accountId => $_getSZ(2);
  @$pb.TagNumber(3)
  set accountId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountId() => $_clearField(3);

  /// Defaults to the plan's category. Must be the caller's.
  @$pb.TagNumber(4)
  $core.String get categoryId => $_getSZ(3);
  @$pb.TagNumber(4)
  set categoryId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCategoryId() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategoryId() => $_clearField(4);
}

/// The result of a confirmation: the occurrence, now COMPLETED, and the ONE Record it became. The
/// record carries plan_id and plan_occurrence_id, which is the plan link.
class ConfirmOccurrenceResponse extends $pb.GeneratedMessage {
  factory ConfirmOccurrenceResponse({
    PlanOccurrence? occurrence,
    $0.Record? record,
  }) {
    final result = create();
    if (occurrence != null) result.occurrence = occurrence;
    if (record != null) result.record = record;
    return result;
  }

  ConfirmOccurrenceResponse._();

  factory ConfirmOccurrenceResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfirmOccurrenceResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfirmOccurrenceResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOM<PlanOccurrence>(1, _omitFieldNames ? '' : 'occurrence',
        subBuilder: PlanOccurrence.create)
    ..aOM<$0.Record>(2, _omitFieldNames ? '' : 'record',
        subBuilder: $0.Record.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmOccurrenceResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfirmOccurrenceResponse copyWith(
          void Function(ConfirmOccurrenceResponse) updates) =>
      super.copyWith((message) => updates(message as ConfirmOccurrenceResponse))
          as ConfirmOccurrenceResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfirmOccurrenceResponse create() => ConfirmOccurrenceResponse._();
  @$core.override
  ConfirmOccurrenceResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfirmOccurrenceResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfirmOccurrenceResponse>(create);
  static ConfirmOccurrenceResponse? _defaultInstance;

  @$pb.TagNumber(1)
  PlanOccurrence get occurrence => $_getN(0);
  @$pb.TagNumber(1)
  set occurrence(PlanOccurrence value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOccurrence() => $_has(0);
  @$pb.TagNumber(1)
  void clearOccurrence() => $_clearField(1);
  @$pb.TagNumber(1)
  PlanOccurrence ensureOccurrence() => $_ensure(0);

  @$pb.TagNumber(2)
  $0.Record get record => $_getN(1);
  @$pb.TagNumber(2)
  set record($0.Record value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRecord() => $_has(1);
  @$pb.TagNumber(2)
  void clearRecord() => $_clearField(2);
  @$pb.TagNumber(2)
  $0.Record ensureRecord() => $_ensure(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
