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

import 'package:protobuf/protobuf.dart' as $pb;

/// Where a session is in its life. The zero value is UNSPECIFIED and is never stored, for the reason
/// accounts.proto gives for AccountType.
class ImportSessionState extends $pb.ProtobufEnum {
  static const ImportSessionState IMPORT_SESSION_STATE_UNSPECIFIED =
      ImportSessionState._(
          0, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_UNSPECIFIED');

  /// Parsed successfully; the rows are held and nothing has been classified. The state a session is
  /// created in.
  static const ImportSessionState IMPORT_SESSION_STATE_PARSED =
      ImportSessionState._(
          1, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_PARSED');

  /// Classified and shown; waiting for the user's confirmation. May be previewed again.
  static const ImportSessionState IMPORT_SESSION_STATE_PREVIEWED =
      ImportSessionState._(
          2, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_PREVIEWED');

  /// Written to the ledger. Terminal; the rows have been discarded, the counts remain.
  static const ImportSessionState IMPORT_SESSION_STATE_COMMITTED =
      ImportSessionState._(
          3, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_COMMITTED');

  /// Thrown away by the user. Terminal; the rows have been discarded.
  static const ImportSessionState IMPORT_SESSION_STATE_DISCARDED =
      ImportSessionState._(
          4, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_DISCARDED');

  /// Not confirmed before expires_at_ms. Terminal; the rows have been discarded.
  static const ImportSessionState IMPORT_SESSION_STATE_EXPIRED =
      ImportSessionState._(
          5, _omitEnumNames ? '' : 'IMPORT_SESSION_STATE_EXPIRED');

  static const $core.List<ImportSessionState> values = <ImportSessionState>[
    IMPORT_SESSION_STATE_UNSPECIFIED,
    IMPORT_SESSION_STATE_PARSED,
    IMPORT_SESSION_STATE_PREVIEWED,
    IMPORT_SESSION_STATE_COMMITTED,
    IMPORT_SESSION_STATE_DISCARDED,
    IMPORT_SESSION_STATE_EXPIRED,
  ];

  static final $core.List<ImportSessionState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ImportSessionState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ImportSessionState._(super.value, super.name);
}

/// What the workflow decided about one row.
class ImportRowStatus extends $pb.ProtobufEnum {
  static const ImportRowStatus IMPORT_ROW_STATUS_UNSPECIFIED =
      ImportRowStatus._(
          0, _omitEnumNames ? '' : 'IMPORT_ROW_STATUS_UNSPECIFIED');

  /// Well formed; will be written on commit.
  static const ImportRowStatus IMPORT_ROW_STATUS_ACCEPTED =
      ImportRowStatus._(1, _omitEnumNames ? '' : 'IMPORT_ROW_STATUS_ACCEPTED');

  /// Recognised as already imported. Set only by a preview stage (jlogicsoftware/prudent#75); never
  /// written on commit.
  static const ImportRowStatus IMPORT_ROW_STATUS_DUPLICATE =
      ImportRowStatus._(2, _omitEnumNames ? '' : 'IMPORT_ROW_STATUS_DUPLICATE');

  /// The importer could not make sense of the row. Flagged, never dropped silently; never written.
  static const ImportRowStatus IMPORT_ROW_STATUS_REJECTED =
      ImportRowStatus._(3, _omitEnumNames ? '' : 'IMPORT_ROW_STATUS_REJECTED');

  static const $core.List<ImportRowStatus> values = <ImportRowStatus>[
    IMPORT_ROW_STATUS_UNSPECIFIED,
    IMPORT_ROW_STATUS_ACCEPTED,
    IMPORT_ROW_STATUS_DUPLICATE,
    IMPORT_ROW_STATUS_REJECTED,
  ];

  static final $core.List<ImportRowStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ImportRowStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ImportRowStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
