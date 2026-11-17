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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'store.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'store.pbenum.dart';

/// Collection `accounts`, a random id. The wire's `is_default` lives in Settings (one field, so two
/// devices cannot leave two defaults) and its `balances` are derived: opening amounts are
/// AccountCurrency records, the current balance is computed from them and the records (F-03).
class Account extends $pb.GeneratedMessage {
  factory Account({
    $core.String? id,
    $core.String? name,
    AccountKind? kind,
    $core.bool? active,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
    $core.bool? eligibleForGoals,
    $core.String? accountNumber,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (kind != null) result.kind = kind;
    if (active != null) result.active = active;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    if (eligibleForGoals != null) result.eligibleForGoals = eligibleForGoals;
    if (accountNumber != null) result.accountNumber = accountNumber;
    return result;
  }

  Account._();

  factory Account.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Account.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Account',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<AccountKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: AccountKind.values)
    ..aOB(4, _omitFieldNames ? '' : 'active')
    ..aOB(5, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(6, _omitFieldNames ? '' : 'includeInOverview')
    ..aOB(7, _omitFieldNames ? '' : 'eligibleForGoals')
    ..aOS(8, _omitFieldNames ? '' : 'accountNumber')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Account clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Account copyWith(void Function(Account) updates) =>
      super.copyWith((message) => updates(message as Account)) as Account;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Account create() => Account._();
  @$core.override
  Account createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Account getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Account>(create);
  static Account? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  AccountKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(AccountKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get active => $_getBF(3);
  @$pb.TagNumber(4)
  set active($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasActive() => $_has(3);
  @$pb.TagNumber(4)
  void clearActive() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get includeInTotal => $_getBF(4);
  @$pb.TagNumber(5)
  set includeInTotal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIncludeInTotal() => $_has(4);
  @$pb.TagNumber(5)
  void clearIncludeInTotal() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeInOverview => $_getBF(5);
  @$pb.TagNumber(6)
  set includeInOverview($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeInOverview() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeInOverview() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get eligibleForGoals => $_getBF(6);
  @$pb.TagNumber(7)
  set eligibleForGoals($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEligibleForGoals() => $_has(6);
  @$pb.TagNumber(7)
  void clearEligibleForGoals() => $_clearField(7);

  /// Normalised (ADR-090). Unique per person across records: an integrity check, not a store rule.
  @$pb.TagNumber(8)
  $core.String get accountNumber => $_getSZ(7);
  @$pb.TagNumber(8)
  set accountNumber($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAccountNumber() => $_has(7);
  @$pb.TagNumber(8)
  void clearAccountNumber() => $_clearField(8);
}

/// Collection `account_currencies`, id H("account_currency", account_id, currency): one record per
/// account and currency, so two devices adding the same currency write the same record.
class AccountCurrency extends $pb.GeneratedMessage {
  factory AccountCurrency({
    $core.String? id,
    $core.String? accountId,
    $core.String? currency,
    $fixnum.Int64? openingMinor,
    $core.int? position,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (openingMinor != null) result.openingMinor = openingMinor;
    if (position != null) result.position = position;
    return result;
  }

  AccountCurrency._();

  factory AccountCurrency.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AccountCurrency.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AccountCurrency',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'accountId')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aInt64(4, _omitFieldNames ? '' : 'openingMinor')
    ..aI(5, _omitFieldNames ? '' : 'position')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AccountCurrency clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AccountCurrency copyWith(void Function(AccountCurrency) updates) =>
      super.copyWith((message) => updates(message as AccountCurrency))
          as AccountCurrency;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AccountCurrency create() => AccountCurrency._();
  @$core.override
  AccountCurrency createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AccountCurrency getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AccountCurrency>(create);
  static AccountCurrency? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get accountId => $_getSZ(1);
  @$pb.TagNumber(2)
  set accountId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get openingMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set openingMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOpeningMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearOpeningMinor() => $_clearField(4);

  /// Display order only; equal positions are ordered by currency code.
  @$pb.TagNumber(5)
  $core.int get position => $_getIZ(4);
  @$pb.TagNumber(5)
  set position($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPosition() => $_has(4);
  @$pb.TagNumber(5)
  void clearPosition() => $_clearField(5);
}

/// Collection `categories`, a random id or H("starter", key).
class Category extends $pb.GeneratedMessage {
  factory Category({
    $core.String? id,
    $core.String? title,
    $core.String? iconKey,
    $core.String? description,
    $core.int? colorArgb,
    $core.bool? archived,
    CategoryDirection? kind,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (iconKey != null) result.iconKey = iconKey;
    if (description != null) result.description = description;
    if (colorArgb != null) result.colorArgb = colorArgb;
    if (archived != null) result.archived = archived;
    if (kind != null) result.kind = kind;
    return result;
  }

  Category._();

  factory Category.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Category.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Category',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'iconKey')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..aI(5, _omitFieldNames ? '' : 'colorArgb', fieldType: $pb.PbFieldType.OU3)
    ..aOB(6, _omitFieldNames ? '' : 'archived')
    ..aE<CategoryDirection>(7, _omitFieldNames ? '' : 'kind',
        enumValues: CategoryDirection.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Category clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Category copyWith(void Function(Category) updates) =>
      super.copyWith((message) => updates(message as Category)) as Category;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Category create() => Category._();
  @$core.override
  Category createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Category getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Category>(create);
  static Category? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get iconKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set iconKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIconKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearIconKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get colorArgb => $_getIZ(4);
  @$pb.TagNumber(5)
  set colorArgb($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasColorArgb() => $_has(4);
  @$pb.TagNumber(5)
  void clearColorArgb() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get archived => $_getBF(5);
  @$pb.TagNumber(6)
  set archived($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasArchived() => $_has(5);
  @$pb.TagNumber(6)
  void clearArchived() => $_clearField(6);

  @$pb.TagNumber(7)
  CategoryDirection get kind => $_getN(6);
  @$pb.TagNumber(7)
  set kind(CategoryDirection value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasKind() => $_has(6);
  @$pb.TagNumber(7)
  void clearKind() => $_clearField(7);
}

/// Where money is and how much of it: one field, so an account, a currency and an amount from two
/// devices never combine into a posting neither wrote ("60 EUR" from a currency change and an amount
/// change).
class Posting extends $pb.GeneratedMessage {
  factory Posting({
    $core.String? accountId,
    $core.String? currency,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  Posting._();

  factory Posting.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Posting.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Posting',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'currency')
    ..aInt64(3, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Posting clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Posting copyWith(void Function(Posting) updates) =>
      super.copyWith((message) => updates(message as Posting)) as Posting;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Posting create() => Posting._();
  @$core.override
  Posting createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Posting getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Posting>(create);
  static Posting? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get currency => $_getSZ(1);
  @$pb.TagNumber(2)
  set currency($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrency() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get amountMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set amountMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmountMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmountMinor() => $_clearField(3);
}

/// What a correction was asked to achieve (D7): the balance requested and the balance it saw. The
/// record's posting keeps the server's meaning, the delta; these let the integrity check notice when
/// a merge changed the correction's effect. Immutable.
class CorrectionIntent extends $pb.GeneratedMessage {
  factory CorrectionIntent({
    $fixnum.Int64? targetMinor,
    $fixnum.Int64? seenMinor,
    $core.Iterable<$core.String>? seenCorrections,
  }) {
    final result = create();
    if (targetMinor != null) result.targetMinor = targetMinor;
    if (seenMinor != null) result.seenMinor = seenMinor;
    if (seenCorrections != null) result.seenCorrections.addAll(seenCorrections);
    return result;
  }

  CorrectionIntent._();

  factory CorrectionIntent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CorrectionIntent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CorrectionIntent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'targetMinor')
    ..aInt64(2, _omitFieldNames ? '' : 'seenMinor')
    ..pPS(3, _omitFieldNames ? '' : 'seenCorrections')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CorrectionIntent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CorrectionIntent copyWith(void Function(CorrectionIntent) updates) =>
      super.copyWith((message) => updates(message as CorrectionIntent))
          as CorrectionIntent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CorrectionIntent create() => CorrectionIntent._();
  @$core.override
  CorrectionIntent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CorrectionIntent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CorrectionIntent>(create);
  static CorrectionIntent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get targetMinor => $_getI64(0);
  @$pb.TagNumber(1)
  set targetMinor($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTargetMinor() => $_has(0);
  @$pb.TagNumber(1)
  void clearTargetMinor() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get seenMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set seenMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSeenMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeenMinor() => $_clearField(2);

  /// The other corrections of the same account and currency this device held when it wrote this one
  /// (ADR-113). Two corrections neither of which names the other were made without seeing each other —
  /// on two devices offline — and both deltas together overshoot what either person asked for; that
  /// is the integrity issue of D7. A balance alone cannot tell it: a later record legitimately moves a
  /// balance away from what a correction saw.
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get seenCorrections => $_getList(2);
}

/// The occurrence a confirmation completed (ADR-040). Immutable. A link to a deleted plan reads as
/// detached; nothing is written when a plan is deleted.
class PlanLink extends $pb.GeneratedMessage {
  factory PlanLink({
    $core.String? planId,
    $core.String? occurrenceId,
    $core.String? occurrenceDate,
  }) {
    final result = create();
    if (planId != null) result.planId = planId;
    if (occurrenceId != null) result.occurrenceId = occurrenceId;
    if (occurrenceDate != null) result.occurrenceDate = occurrenceDate;
    return result;
  }

  PlanLink._();

  factory PlanLink.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlanLink.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlanLink',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'planId')
    ..aOS(2, _omitFieldNames ? '' : 'occurrenceId')
    ..aOS(3, _omitFieldNames ? '' : 'occurrenceDate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanLink clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlanLink copyWith(void Function(PlanLink) updates) =>
      super.copyWith((message) => updates(message as PlanLink)) as PlanLink;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlanLink create() => PlanLink._();
  @$core.override
  PlanLink createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlanLink getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PlanLink>(create);
  static PlanLink? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get planId => $_getSZ(0);
  @$pb.TagNumber(1)
  set planId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlanId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlanId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get occurrenceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set occurrenceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOccurrenceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOccurrenceId() => $_clearField(2);

  /// The occurrence's civil date (YYYY-MM-DD), kept beside its id because the id is a hash and
  /// cannot be turned back into a date: an occurrence completed under an earlier schedule of its
  /// plan is still listed, as on the server, and only this says which day it fell on (unit 6b).
  /// Immutable with the link.
  @$pb.TagNumber(3)
  $core.String get occurrenceDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set occurrenceDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOccurrenceDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearOccurrenceDate() => $_clearField(3);
}

/// What recognises a re-imported statement row (ADR-091, finding F-02: the wire Record lacks it).
/// Immutable.
class ImportKey extends $pb.GeneratedMessage {
  factory ImportKey({
    $core.String? fingerprint,
    $core.int? occurrence,
  }) {
    final result = create();
    if (fingerprint != null) result.fingerprint = fingerprint;
    if (occurrence != null) result.occurrence = occurrence;
    return result;
  }

  ImportKey._();

  factory ImportKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImportKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportKey',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'fingerprint')
    ..aI(2, _omitFieldNames ? '' : 'occurrence')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportKey copyWith(void Function(ImportKey) updates) =>
      super.copyWith((message) => updates(message as ImportKey)) as ImportKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImportKey create() => ImportKey._();
  @$core.override
  ImportKey createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImportKey getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImportKey>(create);
  static ImportKey? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get fingerprint => $_getSZ(0);
  @$pb.TagNumber(1)
  set fingerprint($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFingerprint() => $_has(0);
  @$pb.TagNumber(1)
  void clearFingerprint() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get occurrence => $_getIZ(1);
  @$pb.TagNumber(2)
  set occurrence($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOccurrence() => $_has(1);
  @$pb.TagNumber(2)
  void clearOccurrence() => $_clearField(2);
}

/// Collection `records`: ordinary records and corrections. A transfer is its own message (D4).
class Record extends $pb.GeneratedMessage {
  factory Record({
    $core.String? id,
    $core.String? title,
    Posting? posting,
    $core.String? date,
    $core.String? categoryId,
    $core.String? payee,
    $core.String? note,
    CorrectionIntent? correction,
    PlanLink? planLink,
    ImportKey? importKey,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (posting != null) result.posting = posting;
    if (date != null) result.date = date;
    if (categoryId != null) result.categoryId = categoryId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    if (correction != null) result.correction = correction;
    if (planLink != null) result.planLink = planLink;
    if (importKey != null) result.importKey = importKey;
    return result;
  }

  Record._();

  factory Record.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Record.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Record',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOM<Posting>(3, _omitFieldNames ? '' : 'posting',
        subBuilder: Posting.create)
    ..aOS(4, _omitFieldNames ? '' : 'date')
    ..aOS(5, _omitFieldNames ? '' : 'categoryId')
    ..aOS(6, _omitFieldNames ? '' : 'payee')
    ..aOS(7, _omitFieldNames ? '' : 'note')
    ..aOM<CorrectionIntent>(8, _omitFieldNames ? '' : 'correction',
        subBuilder: CorrectionIntent.create)
    ..aOM<PlanLink>(9, _omitFieldNames ? '' : 'planLink',
        subBuilder: PlanLink.create)
    ..aOM<ImportKey>(10, _omitFieldNames ? '' : 'importKey',
        subBuilder: ImportKey.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Record clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Record copyWith(void Function(Record) updates) =>
      super.copyWith((message) => updates(message as Record)) as Record;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Record create() => Record._();
  @$core.override
  Record createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Record getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Record>(create);
  static Record? _defaultInstance;

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

  @$pb.TagNumber(3)
  Posting get posting => $_getN(2);
  @$pb.TagNumber(3)
  set posting(Posting value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPosting() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosting() => $_clearField(3);
  @$pb.TagNumber(3)
  Posting ensurePosting() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get date => $_getSZ(3);
  @$pb.TagNumber(4)
  set date($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearDate() => $_clearField(4);

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

  /// Present on a correction; a correction is never edited, only deleted (RecordResource.java:232).
  @$pb.TagNumber(8)
  CorrectionIntent get correction => $_getN(7);
  @$pb.TagNumber(8)
  set correction(CorrectionIntent value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasCorrection() => $_has(7);
  @$pb.TagNumber(8)
  void clearCorrection() => $_clearField(8);
  @$pb.TagNumber(8)
  CorrectionIntent ensureCorrection() => $_ensure(7);

  @$pb.TagNumber(9)
  PlanLink get planLink => $_getN(8);
  @$pb.TagNumber(9)
  set planLink(PlanLink value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasPlanLink() => $_has(8);
  @$pb.TagNumber(9)
  void clearPlanLink() => $_clearField(9);
  @$pb.TagNumber(9)
  PlanLink ensurePlanLink() => $_ensure(8);

  @$pb.TagNumber(10)
  ImportKey get importKey => $_getN(9);
  @$pb.TagNumber(10)
  set importKey(ImportKey value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasImportKey() => $_has(9);
  @$pb.TagNumber(10)
  void clearImportKey() => $_clearField(10);
  @$pb.TagNumber(10)
  ImportKey ensureImportKey() => $_ensure(9);
}

/// Collection `transfers`: ONE immutable record holding both legs, so a leg can never arrive alone
/// (ADR-102). Amounts are positive, as the request carries them; the wire's two leg Records are
/// produced on read, the source leg negative.
class Transfer extends $pb.GeneratedMessage {
  factory Transfer({
    $core.String? id,
    $core.String? title,
    $core.String? date,
    Posting? source,
    Posting? destination,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (date != null) result.date = date;
    if (source != null) result.source = source;
    if (destination != null) result.destination = destination;
    return result;
  }

  Transfer._();

  factory Transfer.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Transfer.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Transfer',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'date')
    ..aOM<Posting>(4, _omitFieldNames ? '' : 'source',
        subBuilder: Posting.create)
    ..aOM<Posting>(5, _omitFieldNames ? '' : 'destination',
        subBuilder: Posting.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transfer clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Transfer copyWith(void Function(Transfer) updates) =>
      super.copyWith((message) => updates(message as Transfer)) as Transfer;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Transfer create() => Transfer._();
  @$core.override
  Transfer createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Transfer getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Transfer>(create);
  static Transfer? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get date => $_getSZ(2);
  @$pb.TagNumber(3)
  set date($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearDate() => $_clearField(3);

  @$pb.TagNumber(4)
  Posting get source => $_getN(3);
  @$pb.TagNumber(4)
  set source(Posting value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(4)
  void clearSource() => $_clearField(4);
  @$pb.TagNumber(4)
  Posting ensureSource() => $_ensure(3);

  @$pb.TagNumber(5)
  Posting get destination => $_getN(4);
  @$pb.TagNumber(5)
  set destination(Posting value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasDestination() => $_has(4);
  @$pb.TagNumber(5)
  void clearDestination() => $_clearField(5);
  @$pb.TagNumber(5)
  Posting ensureDestination() => $_ensure(4);
}

/// Collection `budgets`, id H("budget", category_id, month, currency).
class Budget extends $pb.GeneratedMessage {
  factory Budget({
    $core.String? id,
    $core.String? categoryId,
    $core.String? month,
    $core.String? currency,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (id != null) result.id = id;
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
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'categoryId')
    ..aOS(3, _omitFieldNames ? '' : 'month')
    ..aOS(4, _omitFieldNames ? '' : 'currency')
    ..aInt64(5, _omitFieldNames ? '' : 'amountMinor')
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

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get categoryId => $_getSZ(1);
  @$pb.TagNumber(2)
  set categoryId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCategoryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategoryId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get month => $_getSZ(2);
  @$pb.TagNumber(3)
  set month($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMonth() => $_has(2);
  @$pb.TagNumber(3)
  void clearMonth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get currency => $_getSZ(3);
  @$pb.TagNumber(4)
  set currency($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrency() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrency() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get amountMinor => $_getI64(4);
  @$pb.TagNumber(5)
  set amountMinor($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAmountMinor() => $_has(4);
  @$pb.TagNumber(5)
  void clearAmountMinor() => $_clearField(5);
}

/// Who revoked a carry-over reset, and when. One field: the time without its author is half an
/// audit entry. Revoking on two devices is the same intent, so the field merges by `at_ms` with jZen's
/// group policy (`ZenMergePolicy.earliestBy`, jZenDev/jZen#244): the earlier revocation is kept whole,
/// its author with it (`StorePolicies.budgetResets`).
class Revocation extends $pb.GeneratedMessage {
  factory Revocation({
    $core.String? by,
    $fixnum.Int64? atMs,
  }) {
    final result = create();
    if (by != null) result.by = by;
    if (atMs != null) result.atMs = atMs;
    return result;
  }

  Revocation._();

  factory Revocation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Revocation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Revocation',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'by')
    ..aInt64(2, _omitFieldNames ? '' : 'atMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Revocation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Revocation copyWith(void Function(Revocation) updates) =>
      super.copyWith((message) => updates(message as Revocation)) as Revocation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Revocation create() => Revocation._();
  @$core.override
  Revocation createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Revocation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Revocation>(create);
  static Revocation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get by => $_getSZ(0);
  @$pb.TagNumber(1)
  set by($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBy() => $_has(0);
  @$pb.TagNumber(1)
  void clearBy() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get atMs => $_getI64(1);
  @$pb.TagNumber(2)
  set atMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearAtMs() => $_clearField(2);
}

/// Collection `budget_resets`, a random id. An audit entry: everything but the revocation is
/// immutable (ADR-046). `created_by` and `revocation.by` are this device's id locally.
class BudgetCarryOverReset extends $pb.GeneratedMessage {
  factory BudgetCarryOverReset({
    $core.String? id,
    $core.String? categoryId,
    $core.String? month,
    $core.String? currency,
    $fixnum.Int64? discardedMinor,
    $core.String? note,
    $core.String? createdBy,
    $fixnum.Int64? createdAtMs,
    Revocation? revocation,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (categoryId != null) result.categoryId = categoryId;
    if (month != null) result.month = month;
    if (currency != null) result.currency = currency;
    if (discardedMinor != null) result.discardedMinor = discardedMinor;
    if (note != null) result.note = note;
    if (createdBy != null) result.createdBy = createdBy;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (revocation != null) result.revocation = revocation;
    return result;
  }

  BudgetCarryOverReset._();

  factory BudgetCarryOverReset.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory BudgetCarryOverReset.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BudgetCarryOverReset',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'categoryId')
    ..aOS(3, _omitFieldNames ? '' : 'month')
    ..aOS(4, _omitFieldNames ? '' : 'currency')
    ..aInt64(5, _omitFieldNames ? '' : 'discardedMinor')
    ..aOS(6, _omitFieldNames ? '' : 'note')
    ..aOS(7, _omitFieldNames ? '' : 'createdBy')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAtMs')
    ..aOM<Revocation>(9, _omitFieldNames ? '' : 'revocation',
        subBuilder: Revocation.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BudgetCarryOverReset clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BudgetCarryOverReset copyWith(void Function(BudgetCarryOverReset) updates) =>
      super.copyWith((message) => updates(message as BudgetCarryOverReset))
          as BudgetCarryOverReset;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BudgetCarryOverReset create() => BudgetCarryOverReset._();
  @$core.override
  BudgetCarryOverReset createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static BudgetCarryOverReset getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BudgetCarryOverReset>(create);
  static BudgetCarryOverReset? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get categoryId => $_getSZ(1);
  @$pb.TagNumber(2)
  set categoryId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCategoryId() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategoryId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get month => $_getSZ(2);
  @$pb.TagNumber(3)
  set month($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMonth() => $_has(2);
  @$pb.TagNumber(3)
  void clearMonth() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get currency => $_getSZ(3);
  @$pb.TagNumber(4)
  set currency($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrency() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrency() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get discardedMinor => $_getI64(4);
  @$pb.TagNumber(5)
  set discardedMinor($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDiscardedMinor() => $_has(4);
  @$pb.TagNumber(5)
  void clearDiscardedMinor() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get note => $_getSZ(5);
  @$pb.TagNumber(6)
  set note($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNote() => $_has(5);
  @$pb.TagNumber(6)
  void clearNote() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get createdBy => $_getSZ(6);
  @$pb.TagNumber(7)
  set createdBy($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCreatedBy() => $_has(6);
  @$pb.TagNumber(7)
  void clearCreatedBy() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => $_clearField(8);

  @$pb.TagNumber(9)
  Revocation get revocation => $_getN(8);
  @$pb.TagNumber(9)
  set revocation(Revocation value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasRevocation() => $_has(8);
  @$pb.TagNumber(9)
  void clearRevocation() => $_clearField(9);
  @$pb.TagNumber(9)
  Revocation ensureRevocation() => $_ensure(8);
}

/// Collection `goals`, a random id.
class Goal extends $pb.GeneratedMessage {
  factory Goal({
    $core.String? id,
    $core.String? name,
    $core.String? currency,
    $fixnum.Int64? targetAmountMinor,
    $core.String? targetDate,
    GoalState? status,
    $fixnum.Int64? statusChangedAtMs,
    $fixnum.Int64? createdAtMs,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (currency != null) result.currency = currency;
    if (targetAmountMinor != null) result.targetAmountMinor = targetAmountMinor;
    if (targetDate != null) result.targetDate = targetDate;
    if (status != null) result.status = status;
    if (statusChangedAtMs != null) result.statusChangedAtMs = statusChangedAtMs;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
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
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'currency')
    ..aInt64(4, _omitFieldNames ? '' : 'targetAmountMinor')
    ..aOS(5, _omitFieldNames ? '' : 'targetDate')
    ..aE<GoalState>(6, _omitFieldNames ? '' : 'status',
        enumValues: GoalState.values)
    ..aInt64(7, _omitFieldNames ? '' : 'statusChangedAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'createdAtMs')
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

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get currency => $_getSZ(2);
  @$pb.TagNumber(3)
  set currency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrency() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get targetAmountMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set targetAmountMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetAmountMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetAmountMinor() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get targetDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set targetDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTargetDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearTargetDate() => $_clearField(5);

  /// Completing on two devices is the same state and merges; completing on one and archiving on
  /// another is a question.
  @$pb.TagNumber(6)
  GoalState get status => $_getN(5);
  @$pb.TagNumber(6)
  set status(GoalState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasStatus() => $_has(5);
  @$pb.TagNumber(6)
  void clearStatus() => $_clearField(6);

  /// ZenMergePolicy.earliest (jZenDev/jZen#235): two devices that reached the same status at two
  /// moments keep the first. Field number pinned by store_policies_test.
  @$pb.TagNumber(7)
  $fixnum.Int64 get statusChangedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set statusChangedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStatusChangedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearStatusChangedAtMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => $_clearField(8);
}

/// Collection `goal_allocations`, a random id. Append-only and immutable, as on the server; two
/// devices' entries never meet. `created_by` is this device's id locally.
class GoalAllocation extends $pb.GeneratedMessage {
  factory GoalAllocation({
    $core.String? id,
    AllocationKind? kind,
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
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<AllocationKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: AllocationKind.values)
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

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  AllocationKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(AllocationKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sourceGoalId => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceGoalId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceGoalId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceGoalId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get targetGoalId => $_getSZ(3);
  @$pb.TagNumber(4)
  set targetGoalId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetGoalId() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetGoalId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get currency => $_getSZ(4);
  @$pb.TagNumber(5)
  set currency($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get amountMinor => $_getI64(5);
  @$pb.TagNumber(6)
  set amountMinor($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAmountMinor() => $_has(5);
  @$pb.TagNumber(6)
  void clearAmountMinor() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get note => $_getSZ(6);
  @$pb.TagNumber(7)
  set note($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasNote() => $_has(6);
  @$pb.TagNumber(7)
  void clearNote() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get createdAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCreatedAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearCreatedAtMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get createdBy => $_getSZ(8);
  @$pb.TagNumber(9)
  set createdBy($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCreatedBy() => $_has(8);
  @$pb.TagNumber(9)
  void clearCreatedBy() => $_clearField(9);
}

enum Schedule_End { untilDate, occurrenceCount, notSet }

/// A plan's schedule: one field, because an interval from one device and an end from another would
/// be a schedule nobody chose.
class Schedule extends $pb.GeneratedMessage {
  factory Schedule({
    Frequency? frequency,
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

  Schedule._();

  factory Schedule.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Schedule.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Schedule_End> _Schedule_EndByTag = {
    5: Schedule_End.untilDate,
    6: Schedule_End.occurrenceCount,
    0: Schedule_End.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Schedule',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..oo(0, [5, 6])
    ..aE<Frequency>(1, _omitFieldNames ? '' : 'frequency',
        enumValues: Frequency.values)
    ..aI(2, _omitFieldNames ? '' : 'interval', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'startDate')
    ..aOS(4, _omitFieldNames ? '' : 'timeZone')
    ..aOS(5, _omitFieldNames ? '' : 'untilDate')
    ..aI(6, _omitFieldNames ? '' : 'occurrenceCount',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Schedule clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Schedule copyWith(void Function(Schedule) updates) =>
      super.copyWith((message) => updates(message as Schedule)) as Schedule;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Schedule create() => Schedule._();
  @$core.override
  Schedule createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Schedule getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Schedule>(create);
  static Schedule? _defaultInstance;

  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  Schedule_End whichEnd() => _Schedule_EndByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearEnd() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  Frequency get frequency => $_getN(0);
  @$pb.TagNumber(1)
  set frequency(Frequency value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFrequency() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrequency() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get interval => $_getIZ(1);
  @$pb.TagNumber(2)
  set interval($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasInterval() => $_has(1);
  @$pb.TagNumber(2)
  void clearInterval() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get startDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set startDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartDate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get timeZone => $_getSZ(3);
  @$pb.TagNumber(4)
  set timeZone($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimeZone() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimeZone() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get untilDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set untilDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUntilDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearUntilDate() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get occurrenceCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set occurrenceCount($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOccurrenceCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearOccurrenceCount() => $_clearField(6);
}

/// One field: enabled and lead time belong together (ADR-054).
class ReminderSetting extends $pb.GeneratedMessage {
  factory ReminderSetting({
    $core.bool? enabled,
    $core.int? leadDays,
  }) {
    final result = create();
    if (enabled != null) result.enabled = enabled;
    if (leadDays != null) result.leadDays = leadDays;
    return result;
  }

  ReminderSetting._();

  factory ReminderSetting.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReminderSetting.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReminderSetting',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'enabled')
    ..aI(2, _omitFieldNames ? '' : 'leadDays', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReminderSetting clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReminderSetting copyWith(void Function(ReminderSetting) updates) =>
      super.copyWith((message) => updates(message as ReminderSetting))
          as ReminderSetting;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReminderSetting create() => ReminderSetting._();
  @$core.override
  ReminderSetting createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReminderSetting getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReminderSetting>(create);
  static ReminderSetting? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get enabled => $_getBF(0);
  @$pb.TagNumber(1)
  set enabled($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEnabled() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnabled() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get leadDays => $_getIZ(1);
  @$pb.TagNumber(2)
  set leadDays($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLeadDays() => $_has(1);
  @$pb.TagNumber(2)
  void clearLeadDays() => $_clearField(2);
}

/// Collection `plans`, a random id.
class Plan extends $pb.GeneratedMessage {
  factory Plan({
    $core.String? id,
    $core.String? title,
    Posting? posting,
    $core.String? categoryId,
    $core.String? payee,
    $core.String? note,
    Schedule? schedule,
    ReminderSetting? reminder,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (posting != null) result.posting = posting;
    if (categoryId != null) result.categoryId = categoryId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    if (schedule != null) result.schedule = schedule;
    if (reminder != null) result.reminder = reminder;
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
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOM<Posting>(3, _omitFieldNames ? '' : 'posting',
        subBuilder: Posting.create)
    ..aOS(4, _omitFieldNames ? '' : 'categoryId')
    ..aOS(5, _omitFieldNames ? '' : 'payee')
    ..aOS(6, _omitFieldNames ? '' : 'note')
    ..aOM<Schedule>(7, _omitFieldNames ? '' : 'schedule',
        subBuilder: Schedule.create)
    ..aOM<ReminderSetting>(8, _omitFieldNames ? '' : 'reminder',
        subBuilder: ReminderSetting.create)
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

  @$pb.TagNumber(3)
  Posting get posting => $_getN(2);
  @$pb.TagNumber(3)
  set posting(Posting value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPosting() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosting() => $_clearField(3);
  @$pb.TagNumber(3)
  Posting ensurePosting() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get categoryId => $_getSZ(3);
  @$pb.TagNumber(4)
  set categoryId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCategoryId() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategoryId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get payee => $_getSZ(4);
  @$pb.TagNumber(5)
  set payee($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPayee() => $_has(4);
  @$pb.TagNumber(5)
  void clearPayee() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get note => $_getSZ(5);
  @$pb.TagNumber(6)
  set note($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNote() => $_has(5);
  @$pb.TagNumber(6)
  void clearNote() => $_clearField(6);

  @$pb.TagNumber(7)
  Schedule get schedule => $_getN(6);
  @$pb.TagNumber(7)
  set schedule(Schedule value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSchedule() => $_has(6);
  @$pb.TagNumber(7)
  void clearSchedule() => $_clearField(7);
  @$pb.TagNumber(7)
  Schedule ensureSchedule() => $_ensure(6);

  @$pb.TagNumber(8)
  ReminderSetting get reminder => $_getN(7);
  @$pb.TagNumber(8)
  set reminder(ReminderSetting value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasReminder() => $_has(7);
  @$pb.TagNumber(8)
  void clearReminder() => $_clearField(8);
  @$pb.TagNumber(8)
  ReminderSetting ensureReminder() => $_ensure(7);
}

/// Collection `occurrences`, id H("occurrence", plan_id, date); stored only when it differs from the
/// default (skipped, or a reminder read). Completed and overdue are derived, as are the title, amount
/// and account, which are copied from the plan on read.
class OccurrenceState extends $pb.GeneratedMessage {
  factory OccurrenceState({
    $core.String? id,
    $core.String? planId,
    $core.String? occurrenceDate,
    $core.bool? skipped,
    $fixnum.Int64? reminderReadAtMs,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (planId != null) result.planId = planId;
    if (occurrenceDate != null) result.occurrenceDate = occurrenceDate;
    if (skipped != null) result.skipped = skipped;
    if (reminderReadAtMs != null) result.reminderReadAtMs = reminderReadAtMs;
    return result;
  }

  OccurrenceState._();

  factory OccurrenceState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OccurrenceState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OccurrenceState',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'planId')
    ..aOS(3, _omitFieldNames ? '' : 'occurrenceDate')
    ..aOB(4, _omitFieldNames ? '' : 'skipped')
    ..aInt64(5, _omitFieldNames ? '' : 'reminderReadAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OccurrenceState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OccurrenceState copyWith(void Function(OccurrenceState) updates) =>
      super.copyWith((message) => updates(message as OccurrenceState))
          as OccurrenceState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OccurrenceState create() => OccurrenceState._();
  @$core.override
  OccurrenceState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OccurrenceState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OccurrenceState>(create);
  static OccurrenceState? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get occurrenceDate => $_getSZ(2);
  @$pb.TagNumber(3)
  set occurrenceDate($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOccurrenceDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearOccurrenceDate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get skipped => $_getBF(3);
  @$pb.TagNumber(4)
  set skipped($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSkipped() => $_has(3);
  @$pb.TagNumber(4)
  void clearSkipped() => $_clearField(4);

  /// ZenMergePolicy.earliest: read on two devices keeps the first moment. Clearing it (unread) on one
  /// device against a read on another stays a question. Field number pinned by store_policies_test.
  @$pb.TagNumber(5)
  $fixnum.Int64 get reminderReadAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set reminderReadAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasReminderReadAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearReminderReadAtMs() => $_clearField(5);
}

/// Collection `settings`, the one record with id "settings".
class Settings extends $pb.GeneratedMessage {
  factory Settings({
    $core.String? id,
    $core.String? mainCurrency,
    $core.String? defaultAccountId,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (mainCurrency != null) result.mainCurrency = mainCurrency;
    if (defaultAccountId != null) result.defaultAccountId = defaultAccountId;
    return result;
  }

  Settings._();

  factory Settings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Settings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Settings',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'mainCurrency')
    ..aOS(3, _omitFieldNames ? '' : 'defaultAccountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Settings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Settings copyWith(void Function(Settings) updates) =>
      super.copyWith((message) => updates(message as Settings)) as Settings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Settings create() => Settings._();
  @$core.override
  Settings createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Settings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Settings>(create);
  static Settings? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mainCurrency => $_getSZ(1);
  @$pb.TagNumber(2)
  set mainCurrency($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMainCurrency() => $_has(1);
  @$pb.TagNumber(2)
  void clearMainCurrency() => $_clearField(2);

  /// Moved here from Account.is_default (ADR-102): one field, so "one default" is structural.
  @$pb.TagNumber(3)
  $core.String get defaultAccountId => $_getSZ(2);
  @$pb.TagNumber(3)
  set defaultAccountId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDefaultAccountId() => $_has(2);
  @$pb.TagNumber(3)
  void clearDefaultAccountId() => $_clearField(3);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
