// This is a generated file - do not edit.
//
// Generated from prudent/v1/analytics.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'analytics.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'analytics.pbenum.dart';

/// One category's total spend within the requested scope.
class CategorySpend extends $pb.GeneratedMessage {
  factory CategorySpend({
    $core.String? categoryId,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (categoryId != null) result.categoryId = categoryId;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  CategorySpend._();

  factory CategorySpend.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CategorySpend.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategorySpend',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'categoryId')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategorySpend clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategorySpend copyWith(void Function(CategorySpend) updates) =>
      super.copyWith((message) => updates(message as CategorySpend))
          as CategorySpend;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CategorySpend create() => CategorySpend._();
  @$core.override
  CategorySpend createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CategorySpend getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CategorySpend>(create);
  static CategorySpend? _defaultInstance;

  /// The category, by id. A category deleted after the records it labels still contributed to
  /// still appears here by the id it had; the client resolves the id against the category list it
  /// already holds, exactly as records.proto's Record.category_id does.
  @$pb.TagNumber(1)
  $core.String get categoryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set categoryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCategoryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategoryId() => $_clearField(1);

  /// POSITIVE — the magnitude of expense in this category, never the signed ledger amount. Minor
  /// units, in the response's `currency`.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);
}

/// GET /api/v1/analytics/spend-by-category
///
/// Query parameters: `currency` (required, ISO-4217), `year` (required, e.g. 2026), `month`
/// (optional, 1-12 — a scoped single month; omitted means the whole year named by `year`).
///
/// THE EMPTY CASE: a user with no expenses in scope gets `items` empty, never a `CategorySpend`
/// with a zero amount standing in for "nothing spent" and never a 500. An empty list and "spent
/// zero in one category" are different facts and must stay visually different to a caller.
class SpendByCategoryResponse extends $pb.GeneratedMessage {
  factory SpendByCategoryResponse({
    $core.String? currency,
    $core.Iterable<CategorySpend>? items,
  }) {
    final result = create();
    if (currency != null) result.currency = currency;
    if (items != null) result.items.addAll(items);
    return result;
  }

  SpendByCategoryResponse._();

  factory SpendByCategoryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SpendByCategoryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpendByCategoryResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'currency')
    ..pPM<CategorySpend>(2, _omitFieldNames ? '' : 'items',
        subBuilder: CategorySpend.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpendByCategoryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpendByCategoryResponse copyWith(
          void Function(SpendByCategoryResponse) updates) =>
      super.copyWith((message) => updates(message as SpendByCategoryResponse))
          as SpendByCategoryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpendByCategoryResponse create() => SpendByCategoryResponse._();
  @$core.override
  SpendByCategoryResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SpendByCategoryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SpendByCategoryResponse>(create);
  static SpendByCategoryResponse? _defaultInstance;

  /// Echoes the request's currency, so a client rendering this response has no reason to also
  /// remember which currency it asked for.
  @$pb.TagNumber(1)
  $core.String get currency => $_getSZ(0);
  @$pb.TagNumber(1)
  set currency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrency() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<CategorySpend> get items => $_getList(1);
}

/// One period's total spend.
class PeriodSpend extends $pb.GeneratedMessage {
  factory PeriodSpend({
    $core.String? period,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (period != null) result.period = period;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  PeriodSpend._();

  factory PeriodSpend.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PeriodSpend.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PeriodSpend',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'period')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeriodSpend clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PeriodSpend copyWith(void Function(PeriodSpend) updates) =>
      super.copyWith((message) => updates(message as PeriodSpend))
          as PeriodSpend;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PeriodSpend create() => PeriodSpend._();
  @$core.override
  PeriodSpend createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PeriodSpend getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PeriodSpend>(create);
  static PeriodSpend? _defaultInstance;

  /// ISO-ish and sorts lexicographically in calendar order, matching records.proto's civil-date
  /// convention: "2026-08" for GRANULARITY_MONTH, "2026" for GRANULARITY_YEAR. Never a rendered
  /// month name — the client renders that from its own locale.
  @$pb.TagNumber(1)
  $core.String get period => $_getSZ(0);
  @$pb.TagNumber(1)
  set period($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPeriod() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeriod() => $_clearField(1);

  /// POSITIVE — the magnitude of expense in this period, never the signed ledger amount. Minor
  /// units, in the response's `currency`.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);
}

/// GET /api/v1/analytics/spend-by-period
///
/// Query parameters: `currency` (required, ISO-4217), `granularity` (required,
/// GRANULARITY_MONTH or GRANULARITY_YEAR), `count` (required, 1-60 — the number of trailing
/// buckets, ending at the current period as resolved server-side in UTC (docs/DECISIONS.md
/// ADR-014); a record on the first or last civil day of a bucket is bucketed by that date alone,
/// with no timezone conversion applied to it — see records.proto's Record.date).
///
/// Buckets with no expenses are OMITTED, not returned with a zero amount, for the same reason
/// SpendByCategoryResponse omits empty categories: a caller must be able to tell "no data for this
/// month" from "zero was spent this month" from the shape of the response alone. `periods` is
/// ordered oldest to newest.
class SpendByPeriodResponse extends $pb.GeneratedMessage {
  factory SpendByPeriodResponse({
    $core.String? currency,
    Granularity? granularity,
    $core.Iterable<PeriodSpend>? periods,
  }) {
    final result = create();
    if (currency != null) result.currency = currency;
    if (granularity != null) result.granularity = granularity;
    if (periods != null) result.periods.addAll(periods);
    return result;
  }

  SpendByPeriodResponse._();

  factory SpendByPeriodResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SpendByPeriodResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SpendByPeriodResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'currency')
    ..aE<Granularity>(2, _omitFieldNames ? '' : 'granularity',
        enumValues: Granularity.values)
    ..pPM<PeriodSpend>(3, _omitFieldNames ? '' : 'periods',
        subBuilder: PeriodSpend.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpendByPeriodResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SpendByPeriodResponse copyWith(
          void Function(SpendByPeriodResponse) updates) =>
      super.copyWith((message) => updates(message as SpendByPeriodResponse))
          as SpendByPeriodResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SpendByPeriodResponse create() => SpendByPeriodResponse._();
  @$core.override
  SpendByPeriodResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SpendByPeriodResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SpendByPeriodResponse>(create);
  static SpendByPeriodResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get currency => $_getSZ(0);
  @$pb.TagNumber(1)
  set currency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrency() => $_clearField(1);

  @$pb.TagNumber(2)
  Granularity get granularity => $_getN(1);
  @$pb.TagNumber(2)
  set granularity(Granularity value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasGranularity() => $_has(1);
  @$pb.TagNumber(2)
  void clearGranularity() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<PeriodSpend> get periods => $_getList(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
