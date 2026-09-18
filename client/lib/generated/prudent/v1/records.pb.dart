// This is a generated file - do not edit.
//
// Generated from prudent/v1/records.proto.

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

/// A single transaction, as the server holds it.
class Record extends $pb.GeneratedMessage {
  factory Record({
    $core.String? id,
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? currency,
    $core.String? date,
    $core.String? categoryId,
    $core.String? accountId,
    $core.String? transferId,
    $core.String? payee,
    $core.String? note,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (currency != null) result.currency = currency;
    if (date != null) result.date = date;
    if (categoryId != null) result.categoryId = categoryId;
    if (accountId != null) result.accountId = accountId;
    if (transferId != null) result.transferId = transferId;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
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
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aInt64(3, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(4, _omitFieldNames ? '' : 'currency')
    ..aOS(5, _omitFieldNames ? '' : 'date')
    ..aOS(6, _omitFieldNames ? '' : 'categoryId')
    ..aOS(7, _omitFieldNames ? '' : 'accountId')
    ..aOS(8, _omitFieldNames ? '' : 'transferId')
    ..aOS(9, _omitFieldNames ? '' : 'payee')
    ..aOS(10, _omitFieldNames ? '' : 'note')
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

  /// Server-minted UUID. A create request carries no id: an id from an untrusted client is not
  /// identity.
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

  /// Minor units, exact under addition. See accounts.proto's balance_minor for the full
  /// reasoning and for the JSON-encodes-int64-as-a-string warning that applies here too.
  ///
  /// SIGNED (docs/DECISIONS.md ADR-014): NEGATIVE is an expense (money leaving the account),
  /// POSITIVE is income (money entering it). Zero is rejected — a record with no effect on the
  /// balance is not a transaction. This is also the balance formula: an account's current balance
  /// in a currency is its opening balance (accounts.proto's CurrencyBalance) PLUS the sum of its
  /// records' amount_minor in that currency, with no separate sign flip anywhere in that sum.
  @$pb.TagNumber(3)
  $fixnum.Int64 get amountMinor => $_getI64(2);
  @$pb.TagNumber(3)
  set amountMinor($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAmountMinor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAmountMinor() => $_clearField(3);

  /// WHICH OF THE ACCOUNT'S CURRENCIES THIS RECORD IS DENOMINATED IN. ISO-4217.
  ///
  /// Client-supplied and required, which it did not used to be. When an account held exactly one
  /// currency a record could inherit it, and inheritance was the stronger design because it made
  /// disagreement impossible to express. An account now holds SEVERAL currencies (ADR-008), so
  /// there is nothing to inherit — a record has to say which balance it moved, and only the record
  /// knows.
  ///
  /// What replaces inheritance is a refusal: the server rejects a currency the owning account does
  /// not hold. That is a weaker guarantee — a validation rule rather than an unsayable state — and
  /// it is the price of the feature, named here rather than discovered in Phase 2.
  @$pb.TagNumber(4)
  $core.String get currency => $_getSZ(3);
  @$pb.TagNumber(4)
  set currency($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrency() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrency() => $_clearField(4);

  /// A CIVIL DATE — ISO-8601 `YYYY-MM-DD`, e.g. "2026-08-15" — not an instant.
  ///
  /// A purchase happens on a calendar day. An epoch timestamp would force every reader to pick a
  /// timezone to render in, and at the first daylight-saving boundary a record would shift a day
  /// and, at a month edge, into the wrong month — which in a budget app is a wrong total, not a
  /// cosmetic slip. A date string has no timezone to get wrong, sorts lexicographically in
  /// calendar order, and maps to DATE in Postgres and DateTime-at-midnight-local on the client.
  @$pb.TagNumber(5)
  $core.String get date => $_getSZ(4);
  @$pb.TagNumber(5)
  set date($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearDate() => $_clearField(5);

  /// The owning category, by id. The client resolves it against the category list it already
  /// holds and renders a documented fallback for an id it does not know, rather than throwing.
  ///
  /// OPTIONAL (M1 transfers, jlogicsoftware/prudent#32): absent on a transfer leg, which is
  /// neither income nor expense and so has no spend category to assign. Always present on an
  /// ordinary record — RecordResource still requires one on create/replace.
  @$pb.TagNumber(6)
  $core.String get categoryId => $_getSZ(5);
  @$pb.TagNumber(6)
  set categoryId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCategoryId() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategoryId() => $_clearField(6);

  /// The owning account, by id. REQUIRED — a record with no account is money that left no
  /// account, and a balance computed over such records is arithmetic with a hole in it.
  @$pb.TagNumber(7)
  $core.String get accountId => $_getSZ(6);
  @$pb.TagNumber(7)
  set accountId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAccountId() => $_has(6);
  @$pb.TagNumber(7)
  void clearAccountId() => $_clearField(7);

  /// Set only on a transfer leg: the id shared by both linked records, server-minted by
  /// POST /api/v1/transfers and the handle DELETE /api/v1/transfers/{id} deletes by. Absent on an
  /// ordinary record.
  @$pb.TagNumber(8)
  $core.String get transferId => $_getSZ(7);
  @$pb.TagNumber(8)
  set transferId($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTransferId() => $_has(7);
  @$pb.TagNumber(8)
  void clearTransferId() => $_clearField(8);

  /// Free-text counterparty — who was paid, or who paid the user (jlogicsoftware/prudent#51).
  /// OPTIONAL: a record filed before this field existed has none, and that is not a different
  /// kind of record, just one with a blank field. Distinct from category, which classifies WHAT
  /// the money was for; this says WHO was on the other side of it.
  @$pb.TagNumber(9)
  $core.String get payee => $_getSZ(8);
  @$pb.TagNumber(9)
  set payee($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPayee() => $_has(8);
  @$pb.TagNumber(9)
  void clearPayee() => $_clearField(9);

  /// Free-text note (jlogicsoftware/prudent#51). OPTIONAL for the same reason as payee.
  @$pb.TagNumber(10)
  $core.String get note => $_getSZ(9);
  @$pb.TagNumber(10)
  set note($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNote() => $_has(9);
  @$pb.TagNumber(10)
  void clearNote() => $_clearField(10);
}

/// POST /api/v1/records
class CreateRecordRequest extends $pb.GeneratedMessage {
  factory CreateRecordRequest({
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? date,
    $core.String? categoryId,
    $core.String? accountId,
    $core.String? currency,
    $core.String? payee,
    $core.String? note,
  }) {
    final result = create();
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (date != null) result.date = date;
    if (categoryId != null) result.categoryId = categoryId;
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    return result;
  }

  CreateRecordRequest._();

  factory CreateRecordRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateRecordRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateRecordRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'date')
    ..aOS(4, _omitFieldNames ? '' : 'categoryId')
    ..aOS(5, _omitFieldNames ? '' : 'accountId')
    ..aOS(6, _omitFieldNames ? '' : 'currency')
    ..aOS(7, _omitFieldNames ? '' : 'payee')
    ..aOS(8, _omitFieldNames ? '' : 'note')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecordRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateRecordRequest copyWith(void Function(CreateRecordRequest) updates) =>
      super.copyWith((message) => updates(message as CreateRecordRequest))
          as CreateRecordRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateRecordRequest create() => CreateRecordRequest._();
  @$core.override
  CreateRecordRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateRecordRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateRecordRequest>(create);
  static CreateRecordRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  /// See Record.amount_minor: negative is an expense, positive is income, zero is rejected.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get date => $_getSZ(2);
  @$pb.TagNumber(3)
  set date($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearDate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get categoryId => $_getSZ(3);
  @$pb.TagNumber(4)
  set categoryId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCategoryId() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategoryId() => $_clearField(4);

  /// Required. The server rejects an id that does not exist or is not the caller's.
  @$pb.TagNumber(5)
  $core.String get accountId => $_getSZ(4);
  @$pb.TagNumber(5)
  set accountId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAccountId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAccountId() => $_clearField(5);

  /// Required, and rejected if the account named above does not hold it — see Record.currency.
  @$pb.TagNumber(6)
  $core.String get currency => $_getSZ(5);
  @$pb.TagNumber(6)
  set currency($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCurrency() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrency() => $_clearField(6);

  /// See Record.payee. Optional; absent means none.
  @$pb.TagNumber(7)
  $core.String get payee => $_getSZ(6);
  @$pb.TagNumber(7)
  set payee($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPayee() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayee() => $_clearField(7);

  /// See Record.note. Optional; absent means none.
  @$pb.TagNumber(8)
  $core.String get note => $_getSZ(7);
  @$pb.TagNumber(8)
  set note($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNote() => $_has(7);
  @$pb.TagNumber(8)
  void clearNote() => $_clearField(8);
}

/// PUT /api/v1/records/{id} — a FULL REPLACEMENT, for the presence reason set out in
/// categories.proto.
class UpdateRecordRequest extends $pb.GeneratedMessage {
  factory UpdateRecordRequest({
    $core.String? title,
    $fixnum.Int64? amountMinor,
    $core.String? date,
    $core.String? categoryId,
    $core.String? accountId,
    $core.String? currency,
    $core.String? payee,
    $core.String? note,
  }) {
    final result = create();
    if (title != null) result.title = title;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (date != null) result.date = date;
    if (categoryId != null) result.categoryId = categoryId;
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (payee != null) result.payee = payee;
    if (note != null) result.note = note;
    return result;
  }

  UpdateRecordRequest._();

  factory UpdateRecordRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateRecordRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateRecordRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aInt64(2, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'date')
    ..aOS(4, _omitFieldNames ? '' : 'categoryId')
    ..aOS(5, _omitFieldNames ? '' : 'accountId')
    ..aOS(6, _omitFieldNames ? '' : 'currency')
    ..aOS(7, _omitFieldNames ? '' : 'payee')
    ..aOS(8, _omitFieldNames ? '' : 'note')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRecordRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateRecordRequest copyWith(void Function(UpdateRecordRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateRecordRequest))
          as UpdateRecordRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateRecordRequest create() => UpdateRecordRequest._();
  @$core.override
  UpdateRecordRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateRecordRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateRecordRequest>(create);
  static UpdateRecordRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  /// See Record.amount_minor: negative is an expense, positive is income, zero is rejected.
  @$pb.TagNumber(2)
  $fixnum.Int64 get amountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set amountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get date => $_getSZ(2);
  @$pb.TagNumber(3)
  set date($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDate() => $_has(2);
  @$pb.TagNumber(3)
  void clearDate() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get categoryId => $_getSZ(3);
  @$pb.TagNumber(4)
  set categoryId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCategoryId() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategoryId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get accountId => $_getSZ(4);
  @$pb.TagNumber(5)
  set accountId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAccountId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAccountId() => $_clearField(5);

  /// Moving a record between accounts and changing its currency are the same operation here, and
  /// the pair is validated together: the new currency must be one the new account holds.
  @$pb.TagNumber(6)
  $core.String get currency => $_getSZ(5);
  @$pb.TagNumber(6)
  set currency($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCurrency() => $_has(5);
  @$pb.TagNumber(6)
  void clearCurrency() => $_clearField(6);

  /// See Record.payee. Optional; absent on a FULL REPLACEMENT clears any existing payee.
  @$pb.TagNumber(7)
  $core.String get payee => $_getSZ(6);
  @$pb.TagNumber(7)
  set payee($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPayee() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayee() => $_clearField(7);

  /// See Record.note. Optional; absent on a FULL REPLACEMENT clears any existing note.
  @$pb.TagNumber(8)
  $core.String get note => $_getSZ(7);
  @$pb.TagNumber(8)
  set note($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNote() => $_has(7);
  @$pb.TagNumber(8)
  void clearNote() => $_clearField(8);
}

/// GET /api/v1/records — every record owned by the authenticated user.
///
/// UNPAGINATED IN v1, and this is a decision rather than an oversight. jZen's zen.v1.PageRequest
/// exists for list endpoints that need it; a personal expense tracker's record list is bounded
/// by one person's spending, and pagination would arrive here as a page parameter no screen
/// sends and no test exercises. When a real list gets long enough to need it, the page
/// parameters are query parameters on the GET and this message gains its page metadata — a
/// backward-compatible addition, because adding fields is what proto3 is good at.
class ListRecordsResponse extends $pb.GeneratedMessage {
  factory ListRecordsResponse({
    $core.Iterable<Record>? records,
  }) {
    final result = create();
    if (records != null) result.records.addAll(records);
    return result;
  }

  ListRecordsResponse._();

  factory ListRecordsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListRecordsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRecordsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<Record>(1, _omitFieldNames ? '' : 'records',
        subBuilder: Record.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRecordsResponse copyWith(void Function(ListRecordsResponse) updates) =>
      super.copyWith((message) => updates(message as ListRecordsResponse))
          as ListRecordsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListRecordsResponse create() => ListRecordsResponse._();
  @$core.override
  ListRecordsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListRecordsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRecordsResponse>(create);
  static ListRecordsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Record> get records => $_getList(0);
}

/// POST /api/v1/transfers — atomically creates two linked records moving money between two of the
/// caller's own accounts. Both legs carry their OWN amount and currency (jlogicsoftware/prudent#50,
/// ADR-032): a same-currency transfer is the case where they happen to agree, not a distinct mode.
/// NO FX RATE IS EVER COMPUTED — see ADR-008/ADR-009 — the user enters both amounts explicitly and
/// the server persists exactly what was entered. Both amounts are positive magnitudes: the server
/// negates from_amount_minor for the source leg and keeps to_amount_minor positive for the
/// destination leg (see Record.amount_minor, ADR-014).
class CreateTransferRequest extends $pb.GeneratedMessage {
  factory CreateTransferRequest({
    $core.String? title,
    $fixnum.Int64? fromAmountMinor,
    $core.String? fromCurrency,
    $core.String? date,
    $core.String? fromAccountId,
    $core.String? toAccountId,
    $fixnum.Int64? toAmountMinor,
    $core.String? toCurrency,
  }) {
    final result = create();
    if (title != null) result.title = title;
    if (fromAmountMinor != null) result.fromAmountMinor = fromAmountMinor;
    if (fromCurrency != null) result.fromCurrency = fromCurrency;
    if (date != null) result.date = date;
    if (fromAccountId != null) result.fromAccountId = fromAccountId;
    if (toAccountId != null) result.toAccountId = toAccountId;
    if (toAmountMinor != null) result.toAmountMinor = toAmountMinor;
    if (toCurrency != null) result.toCurrency = toCurrency;
    return result;
  }

  CreateTransferRequest._();

  factory CreateTransferRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateTransferRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateTransferRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aInt64(2, _omitFieldNames ? '' : 'fromAmountMinor')
    ..aOS(3, _omitFieldNames ? '' : 'fromCurrency')
    ..aOS(4, _omitFieldNames ? '' : 'date')
    ..aOS(5, _omitFieldNames ? '' : 'fromAccountId')
    ..aOS(6, _omitFieldNames ? '' : 'toAccountId')
    ..aInt64(7, _omitFieldNames ? '' : 'toAmountMinor')
    ..aOS(8, _omitFieldNames ? '' : 'toCurrency')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTransferRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateTransferRequest copyWith(
          void Function(CreateTransferRequest) updates) =>
      super.copyWith((message) => updates(message as CreateTransferRequest))
          as CreateTransferRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateTransferRequest create() => CreateTransferRequest._();
  @$core.override
  CreateTransferRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateTransferRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateTransferRequest>(create);
  static CreateTransferRequest? _defaultInstance;

  /// Optional; blank is stored as "Transfer" server-side. Not load-bearing the way Record.title is.
  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTitle() => $_has(0);
  @$pb.TagNumber(1)
  void clearTitle() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get fromAmountMinor => $_getI64(1);
  @$pb.TagNumber(2)
  set fromAmountMinor($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromAmountMinor() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromAmountMinor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromCurrency => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromCurrency($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFromCurrency() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromCurrency() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get date => $_getSZ(3);
  @$pb.TagNumber(4)
  set date($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearDate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get fromAccountId => $_getSZ(4);
  @$pb.TagNumber(5)
  set fromAccountId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFromAccountId() => $_has(4);
  @$pb.TagNumber(5)
  void clearFromAccountId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get toAccountId => $_getSZ(5);
  @$pb.TagNumber(6)
  set toAccountId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasToAccountId() => $_has(5);
  @$pb.TagNumber(6)
  void clearToAccountId() => $_clearField(6);

  /// Independent of from_amount_minor/from_currency — the destination leg's own amount and
  /// currency, exactly as the user entered them. No conversion is derived from the pair.
  @$pb.TagNumber(7)
  $fixnum.Int64 get toAmountMinor => $_getI64(6);
  @$pb.TagNumber(7)
  set toAmountMinor($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasToAmountMinor() => $_has(6);
  @$pb.TagNumber(7)
  void clearToAmountMinor() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get toCurrency => $_getSZ(7);
  @$pb.TagNumber(8)
  set toCurrency($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasToCurrency() => $_has(7);
  @$pb.TagNumber(8)
  void clearToCurrency() => $_clearField(8);
}

/// The response to a transfer create, and what DELETE /api/v1/transfers/{id} deletes by way of
/// `id`. from_record.amount_minor is negative (the source leg); to_record.amount_minor is
/// positive. Neither leg carries a category_id.
class Transfer extends $pb.GeneratedMessage {
  factory Transfer({
    $core.String? id,
    Record? fromRecord,
    Record? toRecord,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (fromRecord != null) result.fromRecord = fromRecord;
    if (toRecord != null) result.toRecord = toRecord;
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
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOM<Record>(2, _omitFieldNames ? '' : 'fromRecord',
        subBuilder: Record.create)
    ..aOM<Record>(3, _omitFieldNames ? '' : 'toRecord',
        subBuilder: Record.create)
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
  Record get fromRecord => $_getN(1);
  @$pb.TagNumber(2)
  set fromRecord(Record value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFromRecord() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromRecord() => $_clearField(2);
  @$pb.TagNumber(2)
  Record ensureFromRecord() => $_ensure(1);

  @$pb.TagNumber(3)
  Record get toRecord => $_getN(2);
  @$pb.TagNumber(3)
  set toRecord(Record value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasToRecord() => $_has(2);
  @$pb.TagNumber(3)
  void clearToRecord() => $_clearField(3);
  @$pb.TagNumber(3)
  Record ensureToRecord() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
