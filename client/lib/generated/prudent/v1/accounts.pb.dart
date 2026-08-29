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

/// One currency an account holds, and how much of it.
///
/// MONEY IS AN INTEGER COUNT OF MINOR UNITS — 1234 is 12.34 PLN — never a float. Binary floating
/// point cannot represent 0.10, and an expense tracker sums thousands of values; a balance wrong by
/// cents is wrong. int64 minor units are exact under addition and need no decimal library on either
/// stack.
///
/// NOTE FOR BOTH CLIENTS: canonical proto3 JSON encodes int64 AS A STRING ("1234"), while Protobuf
/// binary carries it as a number. The two transport modes therefore differ on the wire and must
/// agree after decoding — which is what the round-trip suite asserts.
class CurrencyBalance extends $pb.GeneratedMessage {
  factory CurrencyBalance({
    $core.String? currency,
    $fixnum.Int64? amountMinor,
  }) {
    final result = create();
    if (currency != null) result.currency = currency;
    if (amountMinor != null) result.amountMinor = amountMinor;
    return result;
  }

  CurrencyBalance._();

  factory CurrencyBalance.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CurrencyBalance.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CurrencyBalance',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'currency')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrencyBalance clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CurrencyBalance copyWith(void Function(CurrencyBalance) updates) =>
      super.copyWith((message) => updates(message as CurrencyBalance))
          as CurrencyBalance;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CurrencyBalance create() => CurrencyBalance._();
  @$core.override
  CurrencyBalance createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CurrencyBalance getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CurrencyBalance>(create);
  static CurrencyBalance? _defaultInstance;

  /// ISO-4217 alphabetic code, validated server-side.
  @$pb.TagNumber(1)
  $core.String get currency => $_getSZ(0);
  @$pb.TagNumber(1)
  set currency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrency() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);
}

/// An account, as the server holds it.
///
/// AN ACCOUNT HOLDS SEVERAL CURRENCIES AT ONCE, each with its own balance — the shape a
/// multi-currency account actually has, rather than one currency per account with a separate
/// account per currency. There is still NO FX: the balances are independent, nothing converts
/// between them, and a total is per-currency. Summing across currencies is refused, not done at
/// some rate nobody chose.
class Account extends $pb.GeneratedMessage {
  factory Account({
    $core.String? id,
    $core.String? name,
    AccountType? type,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
    $core.Iterable<CurrencyBalance>? balances,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    if (balances != null) result.balances.addAll(balances);
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
    ..aOB(6, _omitFieldNames ? '' : 'isDefault')
    ..aOB(7, _omitFieldNames ? '' : 'isActive')
    ..aOB(8, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(9, _omitFieldNames ? '' : 'includeInOverview')
    ..pPM<CurrencyBalance>(10, _omitFieldNames ? '' : 'balances',
        subBuilder: CurrencyBalance.create)
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

  /// The account offered first when creating a record. Exactly one per user is true; the server
  /// clears the flag on the previous holder rather than trusting the client to.
  @$pb.TagNumber(6)
  $core.bool get isDefault => $_getBF(3);
  @$pb.TagNumber(6)
  set isDefault($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(6)
  $core.bool hasIsDefault() => $_has(3);
  @$pb.TagNumber(6)
  void clearIsDefault() => $_clearField(6);

  /// Whether the account is in use. An inactive account is kept for its history rather than
  /// deleted.
  @$pb.TagNumber(7)
  $core.bool get isActive => $_getBF(4);
  @$pb.TagNumber(7)
  set isActive($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(7)
  $core.bool hasIsActive() => $_has(4);
  @$pb.TagNumber(7)
  void clearIsActive() => $_clearField(7);

  /// Whether this account counts toward the total balance...
  @$pb.TagNumber(8)
  $core.bool get includeInTotal => $_getBF(5);
  @$pb.TagNumber(8)
  set includeInTotal($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(8)
  $core.bool hasIncludeInTotal() => $_has(5);
  @$pb.TagNumber(8)
  void clearIncludeInTotal() => $_clearField(8);

  /// ...and whether it appears on the overview. Two flags, not one: a savings account a user
  /// wants visible but excluded from spendable funds needs them to differ.
  @$pb.TagNumber(9)
  $core.bool get includeInOverview => $_getBF(6);
  @$pb.TagNumber(9)
  set includeInOverview($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(9)
  $core.bool hasIncludeInOverview() => $_has(6);
  @$pb.TagNumber(9)
  void clearIncludeInOverview() => $_clearField(9);

  /// THE CURRENCIES THIS ACCOUNT HOLDS, one entry each, WITH THE CURRENT DERIVED BALANCE
  /// (docs/DECISIONS.md ADR-014) — the opening balance set at create/update time PLUS the sum of
  /// the account's records in that currency (records.proto's Record.amount_minor is signed, so no
  /// separate sign flip is needed in that sum). The server computes this on every read; nothing
  /// about it is stored beyond the opening amount. Never empty — an account that holds no
  /// currency cannot receive a record, and the server rejects an empty list rather than creating
  /// one that nothing can be spent from.
  ///
  /// The set is DECLARED, not inferred from whatever records happen to arrive. That is what lets
  /// the server reject a record in a currency the account does not hold, instead of silently
  /// opening a new balance because someone mistyped a code.
  ///
  /// At most one entry per currency; the server rejects duplicates. A repeated message is used
  /// rather than a map<string, int64> because a map's ordering is undefined and its proto3 JSON
  /// form differs more sharply between the two transport modes — and because a balance is likely
  /// to grow fields (an as-of date, a hidden flag) that a bare int64 has nowhere to put.
  @$pb.TagNumber(10)
  $pb.PbList<CurrencyBalance> get balances => $_getList(7);
}

/// POST /api/v1/accounts
class CreateAccountRequest extends $pb.GeneratedMessage {
  factory CreateAccountRequest({
    $core.String? name,
    AccountType? type,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
    $core.Iterable<CurrencyBalance>? balances,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    if (balances != null) result.balances.addAll(balances);
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
    ..aOB(5, _omitFieldNames ? '' : 'isDefault')
    ..aOB(6, _omitFieldNames ? '' : 'isActive')
    ..aOB(7, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(8, _omitFieldNames ? '' : 'includeInOverview')
    ..pPM<CurrencyBalance>(9, _omitFieldNames ? '' : 'balances',
        subBuilder: CurrencyBalance.create)
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

  @$pb.TagNumber(5)
  $core.bool get isDefault => $_getBF(2);
  @$pb.TagNumber(5)
  set isDefault($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(5)
  $core.bool hasIsDefault() => $_has(2);
  @$pb.TagNumber(5)
  void clearIsDefault() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isActive => $_getBF(3);
  @$pb.TagNumber(6)
  set isActive($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(6)
  $core.bool hasIsActive() => $_has(3);
  @$pb.TagNumber(6)
  void clearIsActive() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get includeInTotal => $_getBF(4);
  @$pb.TagNumber(7)
  set includeInTotal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeInTotal() => $_has(4);
  @$pb.TagNumber(7)
  void clearIncludeInTotal() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get includeInOverview => $_getBF(5);
  @$pb.TagNumber(8)
  set includeInOverview($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(8)
  $core.bool hasIncludeInOverview() => $_has(5);
  @$pb.TagNumber(8)
  void clearIncludeInOverview() => $_clearField(8);

  /// The currencies the account opens with, and their OPENING balances. REQUIRED and non-empty.
  /// Every later change to the derived balance an Account response carries is an act of the
  /// records, not of this field — see Account.balances.
  @$pb.TagNumber(9)
  $pb.PbList<CurrencyBalance> get balances => $_getList(6);
}

/// PUT /api/v1/accounts/{id} — a FULL REPLACEMENT, for the presence reason set out in
/// categories.proto.
///
/// The four booleans are why that rule is written down rather than assumed: plain proto3 scalars
/// have no presence, so a client sending `include_in_total = false` and a client that never
/// touched the field produce byte-identical requests. Replacement makes them mean the same
/// thing on purpose, instead of leaving the server to guess which one it received.
class UpdateAccountRequest extends $pb.GeneratedMessage {
  factory UpdateAccountRequest({
    $core.String? name,
    AccountType? type,
    $core.bool? isDefault,
    $core.bool? isActive,
    $core.bool? includeInTotal,
    $core.bool? includeInOverview,
    $core.Iterable<CurrencyBalance>? balances,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (isDefault != null) result.isDefault = isDefault;
    if (isActive != null) result.isActive = isActive;
    if (includeInTotal != null) result.includeInTotal = includeInTotal;
    if (includeInOverview != null) result.includeInOverview = includeInOverview;
    if (balances != null) result.balances.addAll(balances);
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
    ..aOB(4, _omitFieldNames ? '' : 'isDefault')
    ..aOB(5, _omitFieldNames ? '' : 'isActive')
    ..aOB(6, _omitFieldNames ? '' : 'includeInTotal')
    ..aOB(7, _omitFieldNames ? '' : 'includeInOverview')
    ..pPM<CurrencyBalance>(8, _omitFieldNames ? '' : 'balances',
        subBuilder: CurrencyBalance.create)
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

  @$pb.TagNumber(4)
  $core.bool get isDefault => $_getBF(2);
  @$pb.TagNumber(4)
  set isDefault($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasIsDefault() => $_has(2);
  @$pb.TagNumber(4)
  void clearIsDefault() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isActive => $_getBF(3);
  @$pb.TagNumber(5)
  set isActive($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(5)
  $core.bool hasIsActive() => $_has(3);
  @$pb.TagNumber(5)
  void clearIsActive() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeInTotal => $_getBF(4);
  @$pb.TagNumber(6)
  set includeInTotal($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeInTotal() => $_has(4);
  @$pb.TagNumber(6)
  void clearIncludeInTotal() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get includeInOverview => $_getBF(5);
  @$pb.TagNumber(7)
  set includeInOverview($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(7)
  $core.bool hasIncludeInOverview() => $_has(5);
  @$pb.TagNumber(7)
  void clearIncludeInOverview() => $_clearField(7);

  /// The account's currencies and their OPENING balances after this update — a full replacement
  /// like every other field here, so an entry the client omits is an entry it is asking to
  /// remove. Changing the opening amount of a currency that already has records re-bases its
  /// derived balance (Account.balances) by the same delta; it does not touch the records.
  ///
  /// TWO SERVER RULES THIS MESSAGE CANNOT EXPRESS, and both are refusals rather than best-effort
  /// repairs:
  ///
  ///   1. A currency that still has records CANNOT be dropped. Removing it would orphan every
  ///      record denominated in it — money that left an account that no longer admits it exists.
  ///      The server refuses; the user deletes or re-denominates the records first.
  ///   2. A currency CODE is never edited in place. There is no rename: dropping PLN and adding
  ///      EUR in one request is two operations, and rule 1 catches the case where it would have
  ///      silently reinterpreted 100 PLN as 100 EUR. Adding a new currency to an account is always
  ///      allowed — that is the ordinary way an account becomes multi-currency after the fact.
  @$pb.TagNumber(8)
  $pb.PbList<CurrencyBalance> get balances => $_getList(6);
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
