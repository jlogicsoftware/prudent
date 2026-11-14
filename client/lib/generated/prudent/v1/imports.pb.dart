// This is a generated file - do not edit.
//
// Generated from prudent/v1/imports.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'imports.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'imports.pbenum.dart';

/// One normalised statement row. Carries personal data (a description and a counterparty), so it
/// exists only while its session is PARSED or PREVIEWED and is deleted when the session ends.
class ImportRow extends $pb.GeneratedMessage {
  factory ImportRow({
    $core.String? sessionId,
    $core.int? rowNumber,
    ImportRowStatus? status,
    $core.String? rejectionCode,
    $core.String? transactionDate,
    $core.String? bookingDate,
    $fixnum.Int64? amountMinor,
    $core.String? description,
    $core.String? counterparty,
    $core.String? counterpartyAccount,
    $core.String? externalId,
  }) {
    final result = create();
    if (sessionId != null) result.sessionId = sessionId;
    if (rowNumber != null) result.rowNumber = rowNumber;
    if (status != null) result.status = status;
    if (rejectionCode != null) result.rejectionCode = rejectionCode;
    if (transactionDate != null) result.transactionDate = transactionDate;
    if (bookingDate != null) result.bookingDate = bookingDate;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (description != null) result.description = description;
    if (counterparty != null) result.counterparty = counterparty;
    if (counterpartyAccount != null)
      result.counterpartyAccount = counterpartyAccount;
    if (externalId != null) result.externalId = externalId;
    return result;
  }

  ImportRow._();

  factory ImportRow.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImportRow.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportRow',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aI(2, _omitFieldNames ? '' : 'rowNumber')
    ..aE<ImportRowStatus>(3, _omitFieldNames ? '' : 'status',
        enumValues: ImportRowStatus.values)
    ..aOS(4, _omitFieldNames ? '' : 'rejectionCode')
    ..aOS(5, _omitFieldNames ? '' : 'transactionDate')
    ..aOS(6, _omitFieldNames ? '' : 'bookingDate')
    ..aInt64(7, _omitFieldNames ? '' : 'amountMinor')
    ..aOS(8, _omitFieldNames ? '' : 'description')
    ..aOS(9, _omitFieldNames ? '' : 'counterparty')
    ..aOS(10, _omitFieldNames ? '' : 'counterpartyAccount')
    ..aOS(11, _omitFieldNames ? '' : 'externalId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportRow clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportRow copyWith(void Function(ImportRow) updates) =>
      super.copyWith((message) => updates(message as ImportRow)) as ImportRow;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImportRow create() => ImportRow._();
  @$core.override
  ImportRow createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImportRow getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImportRow>(create);
  static ImportRow? _defaultInstance;

  /// The session this row belongs to.
  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  /// 1-based position among the statement's transaction rows, as the importer counted them. Names a
  /// row in an error message without quoting it.
  @$pb.TagNumber(2)
  $core.int get rowNumber => $_getIZ(1);
  @$pb.TagNumber(2)
  set rowNumber($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRowNumber() => $_has(1);
  @$pb.TagNumber(2)
  void clearRowNumber() => $_clearField(2);

  @$pb.TagNumber(3)
  ImportRowStatus get status => $_getN(2);
  @$pb.TagNumber(3)
  set status(ImportRowStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  /// Why a row is rejected: a short stable rule code such as `amount.not_decimal`, never row content.
  /// Empty unless status is REJECTED.
  @$pb.TagNumber(4)
  $core.String get rejectionCode => $_getSZ(3);
  @$pb.TagNumber(4)
  set rejectionCode($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRejectionCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearRejectionCode() => $_clearField(4);

  /// ISO-8601 YYYY-MM-DD, a civil date (see Record.date). Absent only on a rejected row.
  @$pb.TagNumber(5)
  $core.String get transactionDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set transactionDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTransactionDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransactionDate() => $_clearField(5);

  /// The bank's booking date, when the format has one.
  @$pb.TagNumber(6)
  $core.String get bookingDate => $_getSZ(5);
  @$pb.TagNumber(6)
  set bookingDate($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBookingDate() => $_has(5);
  @$pb.TagNumber(6)
  void clearBookingDate() => $_clearField(6);

  /// Signed minor units: negative is money out. Absent only on a rejected row.
  @$pb.TagNumber(7)
  $fixnum.Int64 get amountMinor => $_getI64(6);
  @$pb.TagNumber(7)
  set amountMinor($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAmountMinor() => $_has(6);
  @$pb.TagNumber(7)
  void clearAmountMinor() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get description => $_getSZ(7);
  @$pb.TagNumber(8)
  set description($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasDescription() => $_has(7);
  @$pb.TagNumber(8)
  void clearDescription() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get counterparty => $_getSZ(8);
  @$pb.TagNumber(9)
  set counterparty($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCounterparty() => $_has(8);
  @$pb.TagNumber(9)
  void clearCounterparty() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get counterpartyAccount => $_getSZ(9);
  @$pb.TagNumber(10)
  set counterpartyAccount($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasCounterpartyAccount() => $_has(9);
  @$pb.TagNumber(10)
  void clearCounterpartyAccount() => $_clearField(10);

  /// The bank's own identifier for the entry, when the format has one. Whether it is stable enough to
  /// be a duplicate key is the format's contract to say (jlogicsoftware/prudent#75).
  @$pb.TagNumber(11)
  $core.String get externalId => $_getSZ(10);
  @$pb.TagNumber(11)
  set externalId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasExternalId() => $_has(10);
  @$pb.TagNumber(11)
  void clearExternalId() => $_clearField(11);
}

/// A session, as the server holds it.
class ImportSession extends $pb.GeneratedMessage {
  factory ImportSession({
    $core.String? id,
    $core.String? formatId,
    ImportSessionState? state,
    $core.String? accountId,
    $core.String? currency,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? stateChangedAtMs,
    $fixnum.Int64? expiresAtMs,
    $core.int? acceptedRows,
    $core.int? duplicateRows,
    $core.int? rejectedRows,
    $core.Iterable<ImportRow>? rows,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (formatId != null) result.formatId = formatId;
    if (state != null) result.state = state;
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (stateChangedAtMs != null) result.stateChangedAtMs = stateChangedAtMs;
    if (expiresAtMs != null) result.expiresAtMs = expiresAtMs;
    if (acceptedRows != null) result.acceptedRows = acceptedRows;
    if (duplicateRows != null) result.duplicateRows = duplicateRows;
    if (rejectedRows != null) result.rejectedRows = rejectedRows;
    if (rows != null) result.rows.addAll(rows);
    return result;
  }

  ImportSession._();

  factory ImportSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ImportSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImportSession',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'formatId')
    ..aE<ImportSessionState>(3, _omitFieldNames ? '' : 'state',
        enumValues: ImportSessionState.values)
    ..aOS(4, _omitFieldNames ? '' : 'accountId')
    ..aOS(5, _omitFieldNames ? '' : 'currency')
    ..aInt64(6, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(7, _omitFieldNames ? '' : 'stateChangedAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'expiresAtMs')
    ..aI(9, _omitFieldNames ? '' : 'acceptedRows')
    ..aI(10, _omitFieldNames ? '' : 'duplicateRows')
    ..aI(11, _omitFieldNames ? '' : 'rejectedRows')
    ..pPM<ImportRow>(12, _omitFieldNames ? '' : 'rows',
        subBuilder: ImportRow.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImportSession copyWith(void Function(ImportSession) updates) =>
      super.copyWith((message) => updates(message as ImportSession))
          as ImportSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ImportSession create() => ImportSession._();
  @$core.override
  ImportSession createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ImportSession getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImportSession>(create);
  static ImportSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// The format that parsed it, e.g. `erste-pl-csv`.
  @$pb.TagNumber(2)
  $core.String get formatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set formatId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFormatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormatId() => $_clearField(2);

  @$pb.TagNumber(3)
  ImportSessionState get state => $_getN(2);
  @$pb.TagNumber(3)
  set state(ImportSessionState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);

  /// The destination account, once chosen (at parse or at preview); a commit needs it.
  @$pb.TagNumber(4)
  $core.String get accountId => $_getSZ(3);
  @$pb.TagNumber(4)
  set accountId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccountId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccountId() => $_clearField(4);

  /// ISO-4217. One currency per session: a statement that mixes currencies is rejected.
  @$pb.TagNumber(5)
  $core.String get currency => $_getSZ(4);
  @$pb.TagNumber(5)
  set currency($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => $_clearField(5);

  /// Milliseconds since the Unix epoch.
  @$pb.TagNumber(6)
  $fixnum.Int64 get createdAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAtMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get stateChangedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set stateChangedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStateChangedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearStateChangedAtMs() => $_clearField(7);

  /// After this instant the session can no longer be previewed or committed, and its rows are deleted.
  @$pb.TagNumber(8)
  $fixnum.Int64 get expiresAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExpiresAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearExpiresAtMs() => $_clearField(8);

  /// Counts of the rows classified so far. They survive the deletion of the rows. Stored as counted
  /// when the rows were last classified.
  @$pb.TagNumber(9)
  $core.int get acceptedRows => $_getIZ(8);
  @$pb.TagNumber(9)
  set acceptedRows($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAcceptedRows() => $_has(8);
  @$pb.TagNumber(9)
  void clearAcceptedRows() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get duplicateRows => $_getIZ(9);
  @$pb.TagNumber(10)
  set duplicateRows($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDuplicateRows() => $_has(9);
  @$pb.TagNumber(10)
  void clearDuplicateRows() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get rejectedRows => $_getIZ(10);
  @$pb.TagNumber(11)
  set rejectedRows($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRejectedRows() => $_has(10);
  @$pb.TagNumber(11)
  void clearRejectedRows() => $_clearField(11);

  /// The held rows, in row_number order. Filled on a single-session read while the session is PARSED
  /// or PREVIEWED; empty in a list and once the session has ended.
  @$pb.TagNumber(12)
  $pb.PbList<ImportRow> get rows => $_getList(11);
}

/// POST /api/v1/import-sessions — the PARSE phase.
class CreateImportSessionRequest extends $pb.GeneratedMessage {
  factory CreateImportSessionRequest({
    $core.String? formatId,
    $core.List<$core.int>? content,
    $core.String? accountId,
  }) {
    final result = create();
    if (formatId != null) result.formatId = formatId;
    if (content != null) result.content = content;
    if (accountId != null) result.accountId = accountId;
    return result;
  }

  CreateImportSessionRequest._();

  factory CreateImportSessionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateImportSessionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateImportSessionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'formatId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'content', $pb.PbFieldType.OY)
    ..aOS(3, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateImportSessionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateImportSessionRequest copyWith(
          void Function(CreateImportSessionRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CreateImportSessionRequest))
          as CreateImportSessionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateImportSessionRequest create() => CreateImportSessionRequest._();
  @$core.override
  CreateImportSessionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateImportSessionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateImportSessionRequest>(create);
  static CreateImportSessionRequest? _defaultInstance;

  /// Names the importer. An unknown id is a 400 and nothing is parsed.
  @$pb.TagNumber(1)
  $core.String get formatId => $_getSZ(0);
  @$pb.TagNumber(1)
  set formatId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormatId() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormatId() => $_clearField(1);

  /// The statement exactly as downloaded. Read once, parsed, then dropped; never stored.
  @$pb.TagNumber(2)
  $core.List<$core.int> get content => $_getN(1);
  @$pb.TagNumber(2)
  set content($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearContent() => $_clearField(2);

  /// The destination account. Optional here because the preview may set it; when present it must be
  /// the caller's, active, and hold the statement's currency.
  @$pb.TagNumber(3)
  $core.String get accountId => $_getSZ(2);
  @$pb.TagNumber(3)
  set accountId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountId() => $_clearField(3);
}

/// POST /api/v1/import-sessions/{id}/preview — the PREVIEW phase.
class PreviewImportSessionRequest extends $pb.GeneratedMessage {
  factory PreviewImportSessionRequest({
    $core.String? accountId,
  }) {
    final result = create();
    if (accountId != null) result.accountId = accountId;
    return result;
  }

  PreviewImportSessionRequest._();

  factory PreviewImportSessionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PreviewImportSessionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreviewImportSessionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreviewImportSessionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreviewImportSessionRequest copyWith(
          void Function(PreviewImportSessionRequest) updates) =>
      super.copyWith(
              (message) => updates(message as PreviewImportSessionRequest))
          as PreviewImportSessionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PreviewImportSessionRequest create() =>
      PreviewImportSessionRequest._();
  @$core.override
  PreviewImportSessionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PreviewImportSessionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreviewImportSessionRequest>(create);
  static PreviewImportSessionRequest? _defaultInstance;

  /// Sets or replaces the destination account. Omitting it keeps the one the session already has. The
  /// account is validated on every call, so a preview can be repeated with another account.
  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => $_clearField(1);
}

/// POST /api/v1/import-sessions/{id}/commit — the COMMIT phase.
class CommitImportSessionRequest extends $pb.GeneratedMessage {
  factory CommitImportSessionRequest({
    $core.int? confirmedAcceptedRows,
  }) {
    final result = create();
    if (confirmedAcceptedRows != null)
      result.confirmedAcceptedRows = confirmedAcceptedRows;
    return result;
  }

  CommitImportSessionRequest._();

  factory CommitImportSessionRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommitImportSessionRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitImportSessionRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'confirmedAcceptedRows')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitImportSessionRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitImportSessionRequest copyWith(
          void Function(CommitImportSessionRequest) updates) =>
      super.copyWith(
              (message) => updates(message as CommitImportSessionRequest))
          as CommitImportSessionRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommitImportSessionRequest create() => CommitImportSessionRequest._();
  @$core.override
  CommitImportSessionRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommitImportSessionRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommitImportSessionRequest>(create);
  static CommitImportSessionRequest? _defaultInstance;

  /// How many accepted rows the user was shown in the preview. Refused (409) when it differs from
  /// how many the session now holds, so a commit always confirms exactly what was reviewed.
  @$pb.TagNumber(1)
  $core.int get confirmedAcceptedRows => $_getIZ(0);
  @$pb.TagNumber(1)
  set confirmedAcceptedRows($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfirmedAcceptedRows() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfirmedAcceptedRows() => $_clearField(1);
}

/// GET /api/v1/import-sessions — the caller's sessions, newest first, without rows.
class ListImportSessionsResponse extends $pb.GeneratedMessage {
  factory ListImportSessionsResponse({
    $core.Iterable<ImportSession>? sessions,
  }) {
    final result = create();
    if (sessions != null) result.sessions.addAll(sessions);
    return result;
  }

  ListImportSessionsResponse._();

  factory ListImportSessionsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListImportSessionsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListImportSessionsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<ImportSession>(1, _omitFieldNames ? '' : 'sessions',
        subBuilder: ImportSession.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListImportSessionsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListImportSessionsResponse copyWith(
          void Function(ListImportSessionsResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ListImportSessionsResponse))
          as ListImportSessionsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListImportSessionsResponse create() => ListImportSessionsResponse._();
  @$core.override
  ListImportSessionsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListImportSessionsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListImportSessionsResponse>(create);
  static ListImportSessionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ImportSession> get sessions => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
