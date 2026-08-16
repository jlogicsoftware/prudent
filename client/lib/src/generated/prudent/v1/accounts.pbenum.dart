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

import 'package:protobuf/protobuf.dart' as $pb;

/// What kind of account this is. The zero value is UNSPECIFIED and means exactly that.
///
/// proto3 requires a zero value and uses it for any field that was not set, so whichever
/// constant sits at 0 is what an omission decodes to. Putting CASH there would make a client
/// that forgot the field indistinguishable from one that meant cash — a silent data defect that
/// no test catches, because both produce a valid Account. UNSPECIFIED is rejected server-side.
class AccountType extends $pb.ProtobufEnum {
  static const AccountType ACCOUNT_TYPE_UNSPECIFIED =
      AccountType._(0, _omitEnumNames ? '' : 'ACCOUNT_TYPE_UNSPECIFIED');
  static const AccountType ACCOUNT_TYPE_CASH =
      AccountType._(1, _omitEnumNames ? '' : 'ACCOUNT_TYPE_CASH');
  static const AccountType ACCOUNT_TYPE_CARD =
      AccountType._(2, _omitEnumNames ? '' : 'ACCOUNT_TYPE_CARD');
  static const AccountType ACCOUNT_TYPE_CHECKING =
      AccountType._(3, _omitEnumNames ? '' : 'ACCOUNT_TYPE_CHECKING');
  static const AccountType ACCOUNT_TYPE_SAVINGS =
      AccountType._(4, _omitEnumNames ? '' : 'ACCOUNT_TYPE_SAVINGS');

  static const $core.List<AccountType> values = <AccountType>[
    ACCOUNT_TYPE_UNSPECIFIED,
    ACCOUNT_TYPE_CASH,
    ACCOUNT_TYPE_CARD,
    ACCOUNT_TYPE_CHECKING,
    ACCOUNT_TYPE_SAVINGS,
  ];

  static final $core.List<AccountType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static AccountType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AccountType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
