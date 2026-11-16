// This is a generated file - do not edit.
//
// Generated from prudent_local/v1/imports.proto.

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

/// One normalised statement row: the server's ImportRowEntity. Personal data; it exists only while
/// its session is PARSED or PREVIEWED.
class LocalImportRow extends $pb.GeneratedMessage {
  factory LocalImportRow({
    $core.int? rowNumber,
    ImportRowKind? kind,
    $core.String? rejectionCode,
    $core.String? transactionDate,
    $core.String? bookingDate,
    $fixnum.Int64? amountMinor,
    $core.List<$core.int>? description,
    $core.List<$core.int>? counterparty,
    $core.List<$core.int>? counterpartyAccount,
    $core.List<$core.int>? externalId,
    $core.String? duplicateCode,
    $core.String? categoryId,
    $core.String? note,
    $core.bool? includeDuplicate,
    $core.String? hintCode,
    $core.String? fingerprint,
    $core.int? occurrence,
  }) {
    final result = create();
    if (rowNumber != null) result.rowNumber = rowNumber;
    if (kind != null) result.kind = kind;
    if (rejectionCode != null) result.rejectionCode = rejectionCode;
    if (transactionDate != null) result.transactionDate = transactionDate;
    if (bookingDate != null) result.bookingDate = bookingDate;
    if (amountMinor != null) result.amountMinor = amountMinor;
    if (description != null) result.description = description;
    if (counterparty != null) result.counterparty = counterparty;
    if (counterpartyAccount != null)
      result.counterpartyAccount = counterpartyAccount;
    if (externalId != null) result.externalId = externalId;
    if (duplicateCode != null) result.duplicateCode = duplicateCode;
    if (categoryId != null) result.categoryId = categoryId;
    if (note != null) result.note = note;
    if (includeDuplicate != null) result.includeDuplicate = includeDuplicate;
    if (hintCode != null) result.hintCode = hintCode;
    if (fingerprint != null) result.fingerprint = fingerprint;
    if (occurrence != null) result.occurrence = occurrence;
    return result;
  }

  LocalImportRow._();

  factory LocalImportRow.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LocalImportRow.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocalImportRow',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'rowNumber')
    ..aE<ImportRowKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: ImportRowKind.values)
    ..aOS(3, _omitFieldNames ? '' : 'rejectionCode')
    ..aOS(4, _omitFieldNames ? '' : 'transactionDate')
    ..aOS(5, _omitFieldNames ? '' : 'bookingDate')
    ..aInt64(6, _omitFieldNames ? '' : 'amountMinor')
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'description', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        8, _omitFieldNames ? '' : 'counterparty', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        9, _omitFieldNames ? '' : 'counterpartyAccount', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'externalId', $pb.PbFieldType.OY)
    ..aOS(11, _omitFieldNames ? '' : 'duplicateCode')
    ..aOS(12, _omitFieldNames ? '' : 'categoryId')
    ..aOS(13, _omitFieldNames ? '' : 'note')
    ..aOB(14, _omitFieldNames ? '' : 'includeDuplicate')
    ..aOS(15, _omitFieldNames ? '' : 'hintCode')
    ..aOS(16, _omitFieldNames ? '' : 'fingerprint')
    ..aI(17, _omitFieldNames ? '' : 'occurrence')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalImportRow clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalImportRow copyWith(void Function(LocalImportRow) updates) =>
      super.copyWith((message) => updates(message as LocalImportRow))
          as LocalImportRow;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalImportRow create() => LocalImportRow._();
  @$core.override
  LocalImportRow createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LocalImportRow getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocalImportRow>(create);
  static LocalImportRow? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get rowNumber => $_getIZ(0);
  @$pb.TagNumber(1)
  set rowNumber($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRowNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearRowNumber() => $_clearField(1);

  @$pb.TagNumber(2)
  ImportRowKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(ImportRowKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// A rule code, set exactly on a rejected row.
  @$pb.TagNumber(3)
  $core.String get rejectionCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set rejectionCode($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRejectionCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearRejectionCode() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get transactionDate => $_getSZ(3);
  @$pb.TagNumber(4)
  set transactionDate($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTransactionDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearTransactionDate() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get bookingDate => $_getSZ(4);
  @$pb.TagNumber(5)
  set bookingDate($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBookingDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearBookingDate() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get amountMinor => $_getI64(5);
  @$pb.TagNumber(6)
  set amountMinor($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAmountMinor() => $_has(5);
  @$pb.TagNumber(6)
  void clearAmountMinor() => $_clearField(6);

  /// The statement's text, as the exact UTF-8 bytes of what the importer returned. Not `string`:
  /// Dart's UTF-8 decoder, which the protobuf runtime reads every string with, drops a leading
  /// U+FEFF, and a row whose counterparty is only that mark would then be fingerprinted as an empty
  /// one — another key than the server's for the same row (ADR-114). `ImportText` reads them back.
  @$pb.TagNumber(7)
  $core.List<$core.int> get description => $_getN(6);
  @$pb.TagNumber(7)
  set description($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDescription() => $_has(6);
  @$pb.TagNumber(7)
  void clearDescription() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get counterparty => $_getN(7);
  @$pb.TagNumber(8)
  set counterparty($core.List<$core.int> value) => $_setBytes(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCounterparty() => $_has(7);
  @$pb.TagNumber(8)
  void clearCounterparty() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get counterpartyAccount => $_getN(8);
  @$pb.TagNumber(9)
  set counterpartyAccount($core.List<$core.int> value) => $_setBytes(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCounterpartyAccount() => $_has(8);
  @$pb.TagNumber(9)
  void clearCounterpartyAccount() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get externalId => $_getN(9);
  @$pb.TagNumber(10)
  set externalId($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(10)
  $core.bool hasExternalId() => $_has(9);
  @$pb.TagNumber(10)
  void clearExternalId() => $_clearField(10);

  /// `duplicate.already_imported` on a DUPLICATE row; empty otherwise.
  @$pb.TagNumber(11)
  $core.String get duplicateCode => $_getSZ(10);
  @$pb.TagNumber(11)
  set duplicateCode($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDuplicateCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearDuplicateCode() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get categoryId => $_getSZ(11);
  @$pb.TagNumber(12)
  set categoryId($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCategoryId() => $_has(11);
  @$pb.TagNumber(12)
  void clearCategoryId() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get note => $_getSZ(12);
  @$pb.TagNumber(13)
  set note($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasNote() => $_has(12);
  @$pb.TagNumber(13)
  void clearNote() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get includeDuplicate => $_getBF(13);
  @$pb.TagNumber(14)
  set includeDuplicate($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasIncludeDuplicate() => $_has(13);
  @$pb.TagNumber(14)
  void clearIncludeDuplicate() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get hintCode => $_getSZ(14);
  @$pb.TagNumber(15)
  set hintCode($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasHintCode() => $_has(14);
  @$pb.TagNumber(15)
  void clearHintCode() => $_clearField(15);

  /// The row's key in the destination account (ADR-091): set by a preview with a destination, for
  /// every row that is not rejected; cleared by the next preview before it is set again.
  @$pb.TagNumber(16)
  $core.String get fingerprint => $_getSZ(15);
  @$pb.TagNumber(16)
  set fingerprint($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasFingerprint() => $_has(15);
  @$pb.TagNumber(16)
  void clearFingerprint() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get occurrence => $_getIZ(16);
  @$pb.TagNumber(17)
  set occurrence($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasOccurrence() => $_has(16);
  @$pb.TagNumber(17)
  void clearOccurrence() => $_clearField(17);
}

/// Collection `import_sessions` (device-only), a random id: the server's ImportSessionEntity. The
/// `optional` fields are declared with explicit presence (jZenDev/jZen#245): `committed_written` = 0
/// is a commit that wrote nothing, not one that never happened.
class LocalImportSession extends $pb.GeneratedMessage {
  factory LocalImportSession({
    $core.String? id,
    $core.String? formatId,
    ImportPhase? phase,
    $core.String? accountId,
    $core.String? currency,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? phaseChangedAtMs,
    $fixnum.Int64? expiresAtMs,
    $core.int? acceptedRows,
    $core.int? duplicateRows,
    $core.int? rejectedRows,
    $core.Iterable<LocalImportRow>? rows,
    $core.int? committedWritten,
    $core.int? committedAlreadyImported,
    $core.String? defaultExpenseCategoryId,
    $core.String? defaultIncomeCategoryId,
    $core.String? statementIdentity,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (formatId != null) result.formatId = formatId;
    if (phase != null) result.phase = phase;
    if (accountId != null) result.accountId = accountId;
    if (currency != null) result.currency = currency;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (phaseChangedAtMs != null) result.phaseChangedAtMs = phaseChangedAtMs;
    if (expiresAtMs != null) result.expiresAtMs = expiresAtMs;
    if (acceptedRows != null) result.acceptedRows = acceptedRows;
    if (duplicateRows != null) result.duplicateRows = duplicateRows;
    if (rejectedRows != null) result.rejectedRows = rejectedRows;
    if (rows != null) result.rows.addAll(rows);
    if (committedWritten != null) result.committedWritten = committedWritten;
    if (committedAlreadyImported != null)
      result.committedAlreadyImported = committedAlreadyImported;
    if (defaultExpenseCategoryId != null)
      result.defaultExpenseCategoryId = defaultExpenseCategoryId;
    if (defaultIncomeCategoryId != null)
      result.defaultIncomeCategoryId = defaultIncomeCategoryId;
    if (statementIdentity != null) result.statementIdentity = statementIdentity;
    return result;
  }

  LocalImportSession._();

  factory LocalImportSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LocalImportSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LocalImportSession',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'prudent_local.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'formatId')
    ..aE<ImportPhase>(3, _omitFieldNames ? '' : 'phase',
        enumValues: ImportPhase.values)
    ..aOS(4, _omitFieldNames ? '' : 'accountId')
    ..aOS(5, _omitFieldNames ? '' : 'currency')
    ..aInt64(6, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(7, _omitFieldNames ? '' : 'phaseChangedAtMs')
    ..aInt64(8, _omitFieldNames ? '' : 'expiresAtMs')
    ..aI(9, _omitFieldNames ? '' : 'acceptedRows')
    ..aI(10, _omitFieldNames ? '' : 'duplicateRows')
    ..aI(11, _omitFieldNames ? '' : 'rejectedRows')
    ..pPM<LocalImportRow>(12, _omitFieldNames ? '' : 'rows',
        subBuilder: LocalImportRow.create)
    ..aI(13, _omitFieldNames ? '' : 'committedWritten')
    ..aI(14, _omitFieldNames ? '' : 'committedAlreadyImported')
    ..aOS(15, _omitFieldNames ? '' : 'defaultExpenseCategoryId')
    ..aOS(16, _omitFieldNames ? '' : 'defaultIncomeCategoryId')
    ..aOS(17, _omitFieldNames ? '' : 'statementIdentity')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalImportSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LocalImportSession copyWith(void Function(LocalImportSession) updates) =>
      super.copyWith((message) => updates(message as LocalImportSession))
          as LocalImportSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LocalImportSession create() => LocalImportSession._();
  @$core.override
  LocalImportSession createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LocalImportSession getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LocalImportSession>(create);
  static LocalImportSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get formatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set formatId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFormatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormatId() => $_clearField(2);

  @$pb.TagNumber(3)
  ImportPhase get phase => $_getN(2);
  @$pb.TagNumber(3)
  set phase(ImportPhase value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPhase() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhase() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get accountId => $_getSZ(3);
  @$pb.TagNumber(4)
  set accountId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAccountId() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccountId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get currency => $_getSZ(4);
  @$pb.TagNumber(5)
  set currency($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCurrency() => $_has(4);
  @$pb.TagNumber(5)
  void clearCurrency() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get createdAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreatedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreatedAtMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get phaseChangedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set phaseChangedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPhaseChangedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearPhaseChangedAtMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get expiresAtMs => $_getI64(7);
  @$pb.TagNumber(8)
  set expiresAtMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasExpiresAtMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearExpiresAtMs() => $_clearField(8);

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

  /// In row_number order; empty once the session has ended.
  @$pb.TagNumber(12)
  $pb.PbList<LocalImportRow> get rows => $_getList(11);

  @$pb.TagNumber(13)
  $core.int get committedWritten => $_getIZ(12);
  @$pb.TagNumber(13)
  set committedWritten($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasCommittedWritten() => $_has(12);
  @$pb.TagNumber(13)
  void clearCommittedWritten() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get committedAlreadyImported => $_getIZ(13);
  @$pb.TagNumber(14)
  set committedAlreadyImported($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasCommittedAlreadyImported() => $_has(13);
  @$pb.TagNumber(14)
  void clearCommittedAlreadyImported() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get defaultExpenseCategoryId => $_getSZ(14);
  @$pb.TagNumber(15)
  set defaultExpenseCategoryId($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasDefaultExpenseCategoryId() => $_has(14);
  @$pb.TagNumber(15)
  void clearDefaultExpenseCategoryId() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get defaultIncomeCategoryId => $_getSZ(15);
  @$pb.TagNumber(16)
  set defaultIncomeCategoryId($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasDefaultIncomeCategoryId() => $_has(15);
  @$pb.TagNumber(16)
  void clearDefaultIncomeCategoryId() => $_clearField(16);

  /// ParsedStatement.identityOf of the statement's own account (64 hex), kept only while open.
  @$pb.TagNumber(17)
  $core.String get statementIdentity => $_getSZ(16);
  @$pb.TagNumber(17)
  set statementIdentity($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasStatementIdentity() => $_has(16);
  @$pb.TagNumber(17)
  void clearStatementIdentity() => $_clearField(17);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
