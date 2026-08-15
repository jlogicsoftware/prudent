// This is a generated file - do not edit.
//
// Generated from prudent/v1/accounts.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use accountTypeDescriptor instead')
const AccountType$json = {
  '1': 'AccountType',
  '2': [
    {'1': 'ACCOUNT_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'ACCOUNT_TYPE_CASH', '2': 1},
    {'1': 'ACCOUNT_TYPE_CARD', '2': 2},
    {'1': 'ACCOUNT_TYPE_CHECKING', '2': 3},
    {'1': 'ACCOUNT_TYPE_SAVINGS', '2': 4},
  ],
};

/// Descriptor for `AccountType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List accountTypeDescriptor = $convert.base64Decode(
    'CgtBY2NvdW50VHlwZRIcChhBQ0NPVU5UX1RZUEVfVU5TUEVDSUZJRUQQABIVChFBQ0NPVU5UX1'
    'RZUEVfQ0FTSBABEhUKEUFDQ09VTlRfVFlQRV9DQVJEEAISGQoVQUNDT1VOVF9UWVBFX0NIRUNL'
    'SU5HEAMSGAoUQUNDT1VOVF9UWVBFX1NBVklOR1MQBA==');

@$core.Deprecated('Use accountDescriptor instead')
const Account$json = {
  '1': 'Account',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'type',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.AccountType',
      '10': 'type'
    },
    {'1': 'balance_minor', '3': 4, '4': 1, '5': 3, '10': 'balanceMinor'},
    {'1': 'currency', '3': 5, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'is_default', '3': 6, '4': 1, '5': 8, '10': 'isDefault'},
    {'1': 'is_active', '3': 7, '4': 1, '5': 8, '10': 'isActive'},
    {'1': 'include_in_total', '3': 8, '4': 1, '5': 8, '10': 'includeInTotal'},
    {
      '1': 'include_in_overview',
      '3': 9,
      '4': 1,
      '5': 8,
      '10': 'includeInOverview'
    },
  ],
};

/// Descriptor for `Account`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountDescriptor = $convert.base64Decode(
    'CgdBY2NvdW50Eg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEisKBHR5cGUYAy'
    'ABKA4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEiMKDWJhbGFuY2VfbWlub3IYBCAB'
    'KANSDGJhbGFuY2VNaW5vchIaCghjdXJyZW5jeRgFIAEoCVIIY3VycmVuY3kSHQoKaXNfZGVmYX'
    'VsdBgGIAEoCFIJaXNEZWZhdWx0EhsKCWlzX2FjdGl2ZRgHIAEoCFIIaXNBY3RpdmUSKAoQaW5j'
    'bHVkZV9pbl90b3RhbBgIIAEoCFIOaW5jbHVkZUluVG90YWwSLgoTaW5jbHVkZV9pbl9vdmVydm'
    'lldxgJIAEoCFIRaW5jbHVkZUluT3ZlcnZpZXc=');

@$core.Deprecated('Use createAccountRequestDescriptor instead')
const CreateAccountRequest$json = {
  '1': 'CreateAccountRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.AccountType',
      '10': 'type'
    },
    {'1': 'balance_minor', '3': 3, '4': 1, '5': 3, '10': 'balanceMinor'},
    {'1': 'currency', '3': 4, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'is_default', '3': 5, '4': 1, '5': 8, '10': 'isDefault'},
    {'1': 'is_active', '3': 6, '4': 1, '5': 8, '10': 'isActive'},
    {'1': 'include_in_total', '3': 7, '4': 1, '5': 8, '10': 'includeInTotal'},
    {
      '1': 'include_in_overview',
      '3': 8,
      '4': 1,
      '5': 8,
      '10': 'includeInOverview'
    },
  ],
};

/// Descriptor for `CreateAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createAccountRequestDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVBY2NvdW50UmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEisKBHR5cGUYAiABKA'
    '4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEiMKDWJhbGFuY2VfbWlub3IYAyABKANS'
    'DGJhbGFuY2VNaW5vchIaCghjdXJyZW5jeRgEIAEoCVIIY3VycmVuY3kSHQoKaXNfZGVmYXVsdB'
    'gFIAEoCFIJaXNEZWZhdWx0EhsKCWlzX2FjdGl2ZRgGIAEoCFIIaXNBY3RpdmUSKAoQaW5jbHVk'
    'ZV9pbl90b3RhbBgHIAEoCFIOaW5jbHVkZUluVG90YWwSLgoTaW5jbHVkZV9pbl9vdmVydmlldx'
    'gIIAEoCFIRaW5jbHVkZUluT3ZlcnZpZXc=');

@$core.Deprecated('Use updateAccountRequestDescriptor instead')
const UpdateAccountRequest$json = {
  '1': 'UpdateAccountRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.AccountType',
      '10': 'type'
    },
    {'1': 'balance_minor', '3': 3, '4': 1, '5': 3, '10': 'balanceMinor'},
    {'1': 'is_default', '3': 4, '4': 1, '5': 8, '10': 'isDefault'},
    {'1': 'is_active', '3': 5, '4': 1, '5': 8, '10': 'isActive'},
    {'1': 'include_in_total', '3': 6, '4': 1, '5': 8, '10': 'includeInTotal'},
    {
      '1': 'include_in_overview',
      '3': 7,
      '4': 1,
      '5': 8,
      '10': 'includeInOverview'
    },
  ],
};

/// Descriptor for `UpdateAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateAccountRequestDescriptor = $convert.base64Decode(
    'ChRVcGRhdGVBY2NvdW50UmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEisKBHR5cGUYAiABKA'
    '4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEiMKDWJhbGFuY2VfbWlub3IYAyABKANS'
    'DGJhbGFuY2VNaW5vchIdCgppc19kZWZhdWx0GAQgASgIUglpc0RlZmF1bHQSGwoJaXNfYWN0aX'
    'ZlGAUgASgIUghpc0FjdGl2ZRIoChBpbmNsdWRlX2luX3RvdGFsGAYgASgIUg5pbmNsdWRlSW5U'
    'b3RhbBIuChNpbmNsdWRlX2luX292ZXJ2aWV3GAcgASgIUhFpbmNsdWRlSW5PdmVydmlldw==');

@$core.Deprecated('Use listAccountsResponseDescriptor instead')
const ListAccountsResponse$json = {
  '1': 'ListAccountsResponse',
  '2': [
    {
      '1': 'accounts',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Account',
      '10': 'accounts'
    },
  ],
};

/// Descriptor for `ListAccountsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listAccountsResponseDescriptor = $convert.base64Decode(
    'ChRMaXN0QWNjb3VudHNSZXNwb25zZRIvCghhY2NvdW50cxgBIAMoCzITLnBydWRlbnQudjEuQW'
    'Njb3VudFIIYWNjb3VudHM=');
