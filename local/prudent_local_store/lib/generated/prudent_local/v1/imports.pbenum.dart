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

import 'package:protobuf/protobuf.dart' as $pb;

/// The server's ImportState (ADR-089), value for value with the wire's ImportSessionState.
class ImportPhase extends $pb.ProtobufEnum {
  static const ImportPhase IMPORT_PHASE_UNSPECIFIED =
      ImportPhase._(0, _omitEnumNames ? '' : 'IMPORT_PHASE_UNSPECIFIED');
  static const ImportPhase IMPORT_PHASE_PARSED =
      ImportPhase._(1, _omitEnumNames ? '' : 'IMPORT_PHASE_PARSED');
  static const ImportPhase IMPORT_PHASE_PREVIEWED =
      ImportPhase._(2, _omitEnumNames ? '' : 'IMPORT_PHASE_PREVIEWED');
  static const ImportPhase IMPORT_PHASE_COMMITTED =
      ImportPhase._(3, _omitEnumNames ? '' : 'IMPORT_PHASE_COMMITTED');
  static const ImportPhase IMPORT_PHASE_DISCARDED =
      ImportPhase._(4, _omitEnumNames ? '' : 'IMPORT_PHASE_DISCARDED');
  static const ImportPhase IMPORT_PHASE_EXPIRED =
      ImportPhase._(5, _omitEnumNames ? '' : 'IMPORT_PHASE_EXPIRED');

  static const $core.List<ImportPhase> values = <ImportPhase>[
    IMPORT_PHASE_UNSPECIFIED,
    IMPORT_PHASE_PARSED,
    IMPORT_PHASE_PREVIEWED,
    IMPORT_PHASE_COMMITTED,
    IMPORT_PHASE_DISCARDED,
    IMPORT_PHASE_EXPIRED,
  ];

  static final $core.List<ImportPhase?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ImportPhase? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ImportPhase._(super.value, super.name);
}

/// The server's RowStatus, value for value with the wire's ImportRowStatus.
class ImportRowKind extends $pb.ProtobufEnum {
  static const ImportRowKind IMPORT_ROW_KIND_UNSPECIFIED =
      ImportRowKind._(0, _omitEnumNames ? '' : 'IMPORT_ROW_KIND_UNSPECIFIED');
  static const ImportRowKind IMPORT_ROW_KIND_ACCEPTED =
      ImportRowKind._(1, _omitEnumNames ? '' : 'IMPORT_ROW_KIND_ACCEPTED');
  static const ImportRowKind IMPORT_ROW_KIND_DUPLICATE =
      ImportRowKind._(2, _omitEnumNames ? '' : 'IMPORT_ROW_KIND_DUPLICATE');
  static const ImportRowKind IMPORT_ROW_KIND_REJECTED =
      ImportRowKind._(3, _omitEnumNames ? '' : 'IMPORT_ROW_KIND_REJECTED');

  static const $core.List<ImportRowKind> values = <ImportRowKind>[
    IMPORT_ROW_KIND_UNSPECIFIED,
    IMPORT_ROW_KIND_ACCEPTED,
    IMPORT_ROW_KIND_DUPLICATE,
    IMPORT_ROW_KIND_REJECTED,
  ];

  static final $core.List<ImportRowKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ImportRowKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ImportRowKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
