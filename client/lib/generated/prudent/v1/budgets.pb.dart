// This is a generated file - do not edit.
//
// Generated from prudent/v1/budgets.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// One budget: how much may be spent in one category, in one calendar month, in one currency.
class Budget extends $pb.GeneratedMessage {
  factory Budget({
    $core.String? categoryId,
    $core.String? month,
    $core.String? currency,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (categoryId != null) result.categoryId = categoryId;
    if (month != null) result.month = month;
    if (currency != null) result.currency = currency;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  Budget._();

  factory Budget.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Budget.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Budget',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'categoryId')
    ..aOS(2, _omitFieldNames ? '' : 'month')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aInt64(4, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Budget clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Budget copyWith(void Function(Budget) updates) =>
      super.copyWith((message) => updates(message as Budget)) as Budget;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Budget create() => Budget._();
  @$core.override
  Budget createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Budget getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Budget>(create);
  static Budget? _defaultInstance;

  /// The category the money is budgeted for. The caller's own.
  @$pb.TagNumber(1)
  $core.String get categoryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set categoryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCategoryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategoryId() => $_clearField(1);

  /// The calendar month, ISO-8601 YYYY-MM. A month rather than a date because a budget covers the
  /// whole month; there is no day to choose and none to get wrong.
  @$pb.TagNumber(2)
  $core.String get month => $_getSZ(1);
  @$pb.TagNumber(2)
  set month($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMonth() => $_has(1);
  @$pb.TagNumber(2)
  void clearMonth() => $_clearField(2);

  /// ISO-4217. A budget is in ONE currency and is never converted (ADR-009): a category budgeted in
  /// both PLN and EUR has two budgets, each compared only with spending in its own currency.
  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  /// Minor units, POSITIVE: the amount that may be spent, not a signed transaction amount. Zero and
  /// negative are rejected — to have no budget for a slot, delete it. Zero is refused rather than
  /// stored because proto3 decodes an omitted field to 0, so it would make "the client forgot the
  /// amount" indistinguishable from "spend nothing".
  @$pb.TagNumber(4)
  $fixnum.Int64 get amountMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set amountMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAmountMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearAmountMinor() => $_clearField(4);
}

/// PUT /api/v1/budgets/{categoryId}/{month}/{currency} — sets the budget for that slot, creating it
/// (201) or replacing its amount (200). The slot is in the path, so it cannot be edited by this
/// call: moving a budget to another month or category is deleting one slot and setting another.
class SetBudgetRequest extends $pb.GeneratedMessage {
  factory SetBudgetRequest({
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  SetBudgetRequest._();

  factory SetBudgetRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetBudgetRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetBudgetRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetBudgetRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetBudgetRequest copyWith(void Function(SetBudgetRequest) updates) =>
      super.copyWith((message) => updates(message as SetBudgetRequest))
          as SetBudgetRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetBudgetRequest create() => SetBudgetRequest._();
  @$core.override
  SetBudgetRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetBudgetRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetBudgetRequest>(create);
  static SetBudgetRequest? _defaultInstance;

  /// See Budget.amount_minor.
  @$pb.TagNumber(1)
  $fixnum.Int64 get amountMinor => $_getI64(0);
  @$pb.TagNumber(1)
  set amountMinor($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAmountMinor() => $_has(0);
  @$pb.TagNumber(1)
  void clearAmountMinor() => $_clearField(1);
}

/// GET /api/v1/budgets — the caller's budgets, optionally narrowed by the `month` (YYYY-MM) and
/// `categoryId` query parameters. Ordered by month, then currency, then category id, so the order
/// is total. Unpaginated in v1 for the reason records.proto gives for ListRecordsResponse.
class ListBudgetsResponse extends $pb.GeneratedMessage {
  factory ListBudgetsResponse({
    $core.Iterable<Budget>? budgets,
  }) {
    final result = create();
    if (budgets != null) result.budgets.addAll(budgets);
    return result;
  }

  ListBudgetsResponse._();

  factory ListBudgetsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListBudgetsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListBudgetsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<Budget>(1, _omitFieldNames ? '' : 'budgets',
        subBuilder: Budget.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListBudgetsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListBudgetsResponse copyWith(void Function(ListBudgetsResponse) updates) =>
      super.copyWith((message) => updates(message as ListBudgetsResponse))
          as ListBudgetsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListBudgetsResponse create() => ListBudgetsResponse._();
  @$core.override
  ListBudgetsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListBudgetsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListBudgetsResponse>(create);
  static ListBudgetsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Budget> get budgets => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
