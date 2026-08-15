// This is a generated file - do not edit.
//
// Generated from prudent/v1/accounts.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'accounts.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'accounts.pbenum.dart';

/// An account, as the server holds it.
class Account extends $pb.GeneratedMessage {
  factory Account({
    $core.String? id,
    $core.String? name,
    AccountType? type,
    $fixnum.Int64? balanceMinor,
    $core.String? currency,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (balanceMinor != null) result.balanceMinor = balanceMinor;
    if (currency != null) result.currency = currency;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
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
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aE<AccountType>(3, _omitFieldNames ? '' : 'type',
        enumValues: AccountType.values)
    ..aInt64(4, _omitFieldNames ? '' : 'balanceMinor')
    ..aOS(5, _omitFieldNames ? '' : 'currency')
    ..aOB(6, _omitFieldNames ? '' : 'isDefault')
    ..aOB(7, _omitFieldNames ? '' : 'isActive')
    ..aOB(8, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(9, _omitFieldNames ? '' : 'includeInOverview')
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
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  AccountType get type => $_getN(2);
  @$pb.TagNumber(3)
  set type(AccountType value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => $_clearField(3);

  /// MONEY IS AN INTEGER COUNT OF MINOR UNITS — 1234 is 12.34 PLN — never a float.
  /// Binary floating point cannot represent 0.10, and an expense tracker sums thousands of
  /// values; a balance wrong by cents is wrong. int64 minor units are exact under addition and
  /// need no decimal library on either stack.
  ///
  /// NOTE FOR BOTH CLIENTS: canonical proto3 JSON encodes int64 AS A STRING ("1234"), while
  /// Protobuf binary carries it as a number. The two transport modes therefore differ on the
  /// wire and must agree after decoding — which is what the round-trip suite asserts.
  @$pb.TagNumber(4)
  $fixnum.Int64 get balanceMinor => $_getI64(3);
  @$pb.TagNumber(4)
  set balanceMinor($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBalanceMinor() => $_has(3);
  @$pb.TagNumber(4)
  void clearBalanceMinor() => $_clearField(4);

  /// ISO-4217 alphabetic code, validated server-side. Prudent's default is PLN.
  ///
  /// This is the ONLY place a currency is chosen. A record inherits its account's currency and
  /// cannot contradict it (see records.proto), so there is no FX arithmetic and no rate source:
  /// totals are per-currency, and summing across currencies is refused rather than done
  /// silently.
  @$pb.TagNumber(5)
  $core.String get currency => $_getSZ(4);
  @$pb.TagNumber(5)
  set currency($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => $_clearField(5);

  /// The account offered first when creating a record. Exactly one per user is true; the server
  /// clears the flag on the previous holder rather than trusting the client to.
  @$pb.TagNumber(6)
  $core.bool get isDefault => $_getBF(5);
  @$pb.TagNumber(6)
  set isDefault($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsDefault() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsDefault() => $_clearField(6);

  /// Whether the account is in use. An inactive account is kept for its history rather than
  /// deleted.
  @$pb.TagNumber(7)
  $core.bool get isActive => $_getBF(6);
  @$pb.TagNumber(7)
  set isActive($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsActive() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsActive() => $_clearField(7);

  /// Whether this account counts toward the total balance...
  @$pb.TagNumber(8)
  $core.bool get includeInTotal => $_getBF(7);
  @$pb.TagNumber(8)
  set includeInTotal($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIncludeInTotal() => $_has(7);
  @$pb.TagNumber(8)
  void clearIncludeInTotal() => $_clearField(8);

  /// ...and whether it appears on the overview. Two flags, not one: a savings account a user
  /// wants visible but excluded from spendable funds needs them to differ.
  @$pb.TagNumber(9)
  $core.bool get includeInOverview => $_getBF(8);
  @$pb.TagNumber(9)
  set includeInOverview($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIncludeInOverview() => $_has(8);
  @$pb.TagNumber(9)
  void clearIncludeInOverview() => $_clearField(9);
}

/// POST /api/v1/accounts
class CreateAccountRequest extends $pb.GeneratedMessage {
  factory CreateAccountRequest({
    $core.String? name,
    AccountType? type,
    $fixnum.Int64? balanceMinor,
    $core.String? currency,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (balanceMinor != null) result.balanceMinor = balanceMinor;
    if (currency != null) result.currency = currency;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    return result;
  }

  CreateAccountRequest._();

  factory CreateAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aE<AccountType>(2, _omitFieldNames ? '' : 'type',
        enumValues: AccountType.values)
    ..aInt64(3, _omitFieldNames ? '' : 'balanceMinor')
    ..aOS(4, _omitFieldNames ? '' : 'currency')
    ..aOB(5, _omitFieldNames ? '' : 'isDefault')
    ..aOB(6, _omitFieldNames ? '' : 'isActive')
    ..aOB(7, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(8, _omitFieldNames ? '' : 'includeInOverview')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateAccountRequest copyWith(void Function(CreateAccountRequest) updates) =>
      super.copyWith((message) => updates(message as CreateAccountRequest))
          as CreateAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateAccountRequest create() => CreateAccountRequest._();
  @$core.override
  CreateAccountRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateAccountRequest>(create);
  static CreateAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  AccountType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(AccountType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  /// The opening balance. Every later change to it is an act of the records, not of this field.
  @$pb.TagNumber(3)
  $fixnum.Int64 get balanceMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set balanceMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBalanceMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearBalanceMinor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get currency => $_getSZ(3);
  @$pb.TagNumber(4)
  set currency($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrency() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrency() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isDefault => $_getBF(4);
  @$pb.TagNumber(5)
  set isDefault($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsDefault() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsDefault() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isActive => $_getBF(5);
  @$pb.TagNumber(6)
  set isActive($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsActive() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsActive() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get includeInTotal => $_getBF(6);
  @$pb.TagNumber(7)
  set includeInTotal($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeInTotal() => $_has(6);
  @$pb.TagNumber(7)
  void clearIncludeInTotal() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get includeInOverview => $_getBF(7);
  @$pb.TagNumber(8)
  set includeInOverview($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasIncludeInOverview() => $_has(7);
  @$pb.TagNumber(8)
  void clearIncludeInOverview() => $_clearField(8);
}

/// PUT /api/v1/accounts/{id} — a FULL REPLACEMENT, for the presence reason set out in
/// categories.proto.
///
/// The four booleans are why that rule is written down rather than assumed: plain proto3 scalars
/// have no presence, so a client sending `include_in_total = false` and a client that never
/// touched the field produce byte-identical requests. Replacement makes them mean the same
/// thing on purpose, instead of leaving the server to guess which one it received.
///
/// `currency` is deliberately NOT replaceable here: changing an account's currency would
/// reinterpret every existing record's amount without converting it, silently turning 100 PLN
/// into 100 EUR. It is fixed at creation.
class UpdateAccountRequest extends $pb.GeneratedMessage {
  factory UpdateAccountRequest({
    $core.String? name,
    AccountType? type,
    $fixnum.Int64? balanceMinor,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (balanceMinor != null) result.balanceMinor = balanceMinor;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    return result;
  }

  UpdateAccountRequest._();

  factory UpdateAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aE<AccountType>(2, _omitFieldNames ? '' : 'type',
        enumValues: AccountType.values)
    ..aInt64(3, _omitFieldNames ? '' : 'balanceMinor')
    ..aOB(4, _omitFieldNames ? '' : 'isDefault')
    ..aOB(5, _omitFieldNames ? '' : 'isActive')
    ..aOB(6, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(7, _omitFieldNames ? '' : 'includeInOverview')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateAccountRequest copyWith(void Function(UpdateAccountRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateAccountRequest))
          as UpdateAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateAccountRequest create() => UpdateAccountRequest._();
  @$core.override
  UpdateAccountRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateAccountRequest>(create);
  static UpdateAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  AccountType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(AccountType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get balanceMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set balanceMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBalanceMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearBalanceMinor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isDefault => $_getBF(3);
  @$pb.TagNumber(4)
  set isDefault($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsDefault() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsDefault() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isActive => $_getBF(4);
  @$pb.TagNumber(5)
  set isActive($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasIsActive() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsActive() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeInTotal => $_getBF(5);
  @$pb.TagNumber(6)
  set includeInTotal($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeInTotal() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeInTotal() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get includeInOverview => $_getBF(6);
  @$pb.TagNumber(7)
  set includeInOverview($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeInOverview() => $_has(6);
  @$pb.TagNumber(7)
  void clearIncludeInOverview() => $_clearField(7);
}

/// GET /api/v1/accounts — every account owned by the authenticated user.
class ListAccountsResponse extends $pb.GeneratedMessage {
  factory ListAccountsResponse({
    $core.Iterable<Account>? accounts,
  }) {
    final result = create();
    if (accounts != null) result.accounts.addAll(accounts);
    return result;
  }

  ListAccountsResponse._();

  factory ListAccountsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListAccountsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListAccountsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<Account>(1, _omitFieldNames ? '' : 'accounts',
        subBuilder: Account.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListAccountsResponse copyWith(void Function(ListAccountsResponse) updates) =>
      super.copyWith((message) => updates(message as ListAccountsResponse))
          as ListAccountsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListAccountsResponse create() => ListAccountsResponse._();
  @$core.override
  ListAccountsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListAccountsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListAccountsResponse>(create);
  static ListAccountsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Account> get accounts => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
