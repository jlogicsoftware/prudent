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

/// One budgeted category's plan, actual and remaining amount for one month, in one currency (M3,
/// jlogicsoftware/prudent#59, ADR-044; carry-over #60, ADR-045). Calculated on every read from the budget and the ledger and
/// never stored, so it cannot drift from either.
class CategoryBudgetSummary extends $pb.GeneratedMessage {
  factory CategoryBudgetSummary({
    $core.String? categoryId,
    $fixnum.Int64? planMinor,
    $fixnum.Int64? actualMinor,
    $fixnum.Int64? remainingMinor,
    $fixnum.Int64? carryOverMinor,
  }) {
    final result = create();
    if (categoryId != null) result.categoryId = categoryId;
    if (planMinor != null) result.planMinor = planMinor;
    if (actualMinor != null) result.actualMinor = actualMinor;
    if (remainingMinor != null) result.remainingMinor = remainingMinor;
    if (carryOverMinor != null) result.carryOverMinor = carryOverMinor;
    return result;
  }

  CategoryBudgetSummary._();

  factory CategoryBudgetSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CategoryBudgetSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategoryBudgetSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'categoryId')
    ..aInt64(2, _omitFieldNames ? '' : 'planMinor')
    ..aInt64(3, _omitFieldNames ? '' : 'actualMinor')
    ..aInt64(4, _omitFieldNames ? '' : 'remainingMinor')
    ..aInt64(5, _omitFieldNames ? '' : 'carryOverMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryBudgetSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryBudgetSummary copyWith(
          void Function(CategoryBudgetSummary) updates) =>
      super.copyWith((message) => updates(message as CategoryBudgetSummary))
          as CategoryBudgetSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CategoryBudgetSummary create() => CategoryBudgetSummary._();
  @$core.override
  CategoryBudgetSummary createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CategoryBudgetSummary getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CategoryBudgetSummary>(create);
  static CategoryBudgetSummary? _defaultInstance;

  /// The budgeted category. The client resolves the id against the category list it already holds.
  @$pb.TagNumber(1)
  $core.String get categoryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set categoryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCategoryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategoryId() => $_clearField(1);

  /// The budget for this category, month and currency: what may be spent. Positive minor units.
  @$pb.TagNumber(2)
  $fixnum.Int64 get planMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set planMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPlanMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlanMinor() => $_clearField(2);

  /// What was spent, NET OF REFUNDS: the money that left the category's records dated in the month
  /// and in this currency, minus the money that came back into them, from posted records only. A
  /// positive number is net spending; it is negative when refunds outweigh spending in the month.
  /// See ADR-044 for exactly which records count.
  @$pb.TagNumber(3)
  $fixnum.Int64 get actualMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set actualMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasActualMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearActualMinor() => $_clearField(3);

  /// What may still be spent: carry_over_minor + plan_minor - actual_minor. Negative once the
  /// category is overspent, including by an overspend carried in from an earlier month.
  @$pb.TagNumber(4)
  $fixnum.Int64 get remainingMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set remainingMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRemainingMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearRemainingMinor() => $_clearField(4);

  /// What the category's EARLIER budgeted months left over (positive) or overspent (negative),
  /// carried into this month (M3, jlogicsoftware/prudent#60, ADR-045). The sum of
  /// (plan - actual) over every earlier month that has a budget in this currency; a month with no
  /// budget contributes nothing, so the figure passes unchanged across a gap. Zero for a category's
  /// first budgeted month. Calculated on every read, so editing an earlier month's budget or
  /// records changes it.
  @$pb.TagNumber(5)
  $fixnum.Int64 get carryOverMinor => $_getI64(4);
  @$pb.TagNumber(5)
  set carryOverMinor($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCarryOverMinor() => $_has(4);
  @$pb.TagNumber(5)
  void clearCarryOverMinor() => $_clearField(5);
}

/// GET /api/v1/budgets/summary?month=YYYY-MM&currency=XXX — the plan, actual and remaining amount of
/// every category budgeted for that month and currency. BOTH query parameters are required: a
/// summary is for one month in ONE currency, and the currency is never inferred or summed across
/// (ADR-009), so there is no field two currencies could be added into. Categories without a budget
/// in that slot are not listed. Ordered by category id, so the order is total.
class BudgetSummaryResponse extends $pb.GeneratedMessage {
  factory BudgetSummaryResponse({
    $core.String? month,
    $core.String? currency,
    $core.Iterable<CategoryBudgetSummary>? items,
    $fixnum.Int64? totalPlanMinor,
    $fixnum.Int64? totalActualMinor,
    $fixnum.Int64? totalRemainingMinor,
    $fixnum.Int64? totalCarryOverMinor,
  }) {
    final result = create();
    if (month != null) result.month = month;
    if (currency != null) result.currency = currency;
    if (items != null) result.items.addAll(items);
    if (totalPlanMinor != null) result.totalPlanMinor = totalPlanMinor;
    if (totalActualMinor != null) result.totalActualMinor = totalActualMinor;
    if (totalRemainingMinor != null)
      result.totalRemainingMinor = totalRemainingMinor;
    if (totalCarryOverMinor != null)
      result.totalCarryOverMinor = totalCarryOverMinor;
    return result;
  }

  BudgetSummaryResponse._();

  factory BudgetSummaryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BudgetSummaryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BudgetSummaryResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'month')
    ..aOS(2, _omitFieldNames ? '' : 'currency')
    ..pPM<CategoryBudgetSummary>(3, _omitFieldNames ? '' : 'items',
        subBuilder: CategoryBudgetSummary.create)
    ..aInt64(4, _omitFieldNames ? '' : 'totalPlanMinor')
    ..aInt64(5, _omitFieldNames ? '' : 'totalActualMinor')
    ..aInt64(6, _omitFieldNames ? '' : 'totalRemainingMinor')
    ..aInt64(7, _omitFieldNames ? '' : 'totalCarryOverMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BudgetSummaryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BudgetSummaryResponse copyWith(
          void Function(BudgetSummaryResponse) updates) =>
      super.copyWith((message) => updates(message as BudgetSummaryResponse))
          as BudgetSummaryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BudgetSummaryResponse create() => BudgetSummaryResponse._();
  @$core.override
  BudgetSummaryResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BudgetSummaryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BudgetSummaryResponse>(create);
  static BudgetSummaryResponse? _defaultInstance;

  /// The requested month, YYYY-MM, echoed back.
  @$pb.TagNumber(1)
  $core.String get month => $_getSZ(0);
  @$pb.TagNumber(1)
  set month($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMonth() => $_has(0);
  @$pb.TagNumber(1)
  void clearMonth() => $_clearField(1);

  /// The requested currency, normalised to upper case.
  @$pb.TagNumber(2)
  $core.String get currency => $_getSZ(1);
  @$pb.TagNumber(2)
  set currency($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<CategoryBudgetSummary> get items => $_getList(2);

  /// The sums of the items' three amounts, in the response's currency. They cover the budgeted
  /// categories only, so spending in a category with no budget is in none of them.
  @$pb.TagNumber(4)
  $fixnum.Int64 get totalPlanMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set totalPlanMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalPlanMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalPlanMinor() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalActualMinor => $_getI64(4);
  @$pb.TagNumber(5)
  set totalActualMinor($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalActualMinor() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalActualMinor() => $_clearField(5);

  /// Includes the carry-over, like each item's remaining_minor.
  @$pb.TagNumber(6)
  $fixnum.Int64 get totalRemainingMinor => $_getI64(5);
  @$pb.TagNumber(6)
  set totalRemainingMinor($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalRemainingMinor() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalRemainingMinor() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get totalCarryOverMinor => $_getI64(6);
  @$pb.TagNumber(7)
  set totalCarryOverMinor($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalCarryOverMinor() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalCarryOverMinor() => $_clearField(7);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
