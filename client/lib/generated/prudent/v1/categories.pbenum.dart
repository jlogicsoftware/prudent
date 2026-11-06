// This is a generated file - do not edit.
//
// Generated from prudent/v1/categories.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Which side of the ledger a category files records on (jlogicsoftware/prudent#229). A record's
/// sign is its direction (records.proto), so a category is offered, and accepted, only for the
/// direction it names.
class CategoryKind extends $pb.ProtobufEnum {
  /// A category that predates the kind, or one created without it. It is usable for both
  /// directions, so nothing a user already filed changes meaning; editing the category and
  /// choosing a kind is how it leaves this state.
  static const CategoryKind CATEGORY_KIND_UNSPECIFIED =
      CategoryKind._(0, _omitEnumNames ? '' : 'CATEGORY_KIND_UNSPECIFIED');

  /// Files expenses (negative records) only.
  static const CategoryKind CATEGORY_KIND_EXPENSE =
      CategoryKind._(1, _omitEnumNames ? '' : 'CATEGORY_KIND_EXPENSE');

  /// Files income (positive records) only.
  static const CategoryKind CATEGORY_KIND_INCOME =
      CategoryKind._(2, _omitEnumNames ? '' : 'CATEGORY_KIND_INCOME');

  static const $core.List<CategoryKind> values = <CategoryKind>[
    CATEGORY_KIND_UNSPECIFIED,
    CATEGORY_KIND_EXPENSE,
    CATEGORY_KIND_INCOME,
  ];

  static final $core.List<CategoryKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static CategoryKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CategoryKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
