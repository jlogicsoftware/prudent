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

import 'package:protobuf/protobuf.dart' as $pb;

/// The bucketing width for GET /api/v1/analytics/spend-by-period.
///
/// proto3 requires a zero value; GRANULARITY_UNSPECIFIED is rejected server-side rather than
/// defaulted to a month, for the same reason ACCOUNT_TYPE_UNSPECIFIED is rejected in
/// accounts.proto — a default would make "the client forgot" and "the client meant month"
/// indistinguishable.
class Granularity extends $pb.ProtobufEnum {
  static const Granularity GRANULARITY_UNSPECIFIED =
      Granularity._(0, _omitEnumNames ? '' : 'GRANULARITY_UNSPECIFIED');
  static const Granularity GRANULARITY_MONTH =
      Granularity._(1, _omitEnumNames ? '' : 'GRANULARITY_MONTH');
  static const Granularity GRANULARITY_YEAR =
      Granularity._(2, _omitEnumNames ? '' : 'GRANULARITY_YEAR');

  static const $core.List<Granularity> values = <Granularity>[
    GRANULARITY_UNSPECIFIED,
    GRANULARITY_MONTH,
    GRANULARITY_YEAR,
  ];

  static final $core.List<Granularity?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Granularity? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Granularity._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
