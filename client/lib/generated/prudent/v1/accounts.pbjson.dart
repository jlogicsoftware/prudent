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

@$core.Deprecated('Use currencyBalanceDescriptor instead')
const CurrencyBalance$json = {
  '1': 'CurrencyBalance',
  '2': [
    {'1': 'currency', '3': 1, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `CurrencyBalance`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List currencyBalanceDescriptor = $convert.base64Decode(
    'Cg9DdXJyZW5jeUJhbGFuY2USGgoIY3VycmVuY3kYASABKAlSCGN1cnJlbmN5EiEKDGFtb3VudF'
    '9taW5vchgCIAEoA1ILYW1vdW50TWlub3I=');

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
    {
      '1': 'balances',
      '3': 10,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.CurrencyBalance',
      '10': 'balances'
    },
  ],
  '9': [
    {'1': 4, '2': 5},
    {'1': 5, '2': 6},
  ],
  '10': ['balance_minor', 'currency'],
};

/// Descriptor for `Account`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountDescriptor = $convert.base64Decode(
    'CgdBY2NvdW50Eg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEisKBHR5cGUYAy'
    'ABKA4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEh0KCmlzX2RlZmF1bHQYBiABKAhS'
    'CWlzRGVmYXVsdBIbCglpc19hY3RpdmUYByABKAhSCGlzQWN0aXZlEigKEGluY2x1ZGVfaW5fdG'
    '90YWwYCCABKAhSDmluY2x1ZGVJblRvdGFsEi4KE2luY2x1ZGVfaW5fb3ZlcnZpZXcYCSABKAhS'
    'EWluY2x1ZGVJbk92ZXJ2aWV3EjcKCGJhbGFuY2VzGAogAygLMhsucHJ1ZGVudC52MS5DdXJyZW'
    '5jeUJhbGFuY2VSCGJhbGFuY2VzSgQIBBAFSgQIBRAGUg1iYWxhbmNlX21pbm9yUghjdXJyZW5j'
    'eQ==');

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
    {
      '1': 'balances',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.CurrencyBalance',
      '10': 'balances'
    },
  ],
  '9': [
    {'1': 3, '2': 4},
    {'1': 4, '2': 5},
  ],
  '10': ['balance_minor', 'currency'],
};

/// Descriptor for `CreateAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createAccountRequestDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVBY2NvdW50UmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEisKBHR5cGUYAiABKA'
    '4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEh0KCmlzX2RlZmF1bHQYBSABKAhSCWlz'
    'RGVmYXVsdBIbCglpc19hY3RpdmUYBiABKAhSCGlzQWN0aXZlEigKEGluY2x1ZGVfaW5fdG90YW'
    'wYByABKAhSDmluY2x1ZGVJblRvdGFsEi4KE2luY2x1ZGVfaW5fb3ZlcnZpZXcYCCABKAhSEWlu'
    'Y2x1ZGVJbk92ZXJ2aWV3EjcKCGJhbGFuY2VzGAkgAygLMhsucHJ1ZGVudC52MS5DdXJyZW5jeU'
    'JhbGFuY2VSCGJhbGFuY2VzSgQIAxAESgQIBBAFUg1iYWxhbmNlX21pbm9yUghjdXJyZW5jeQ==');

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
    {
      '1': 'balances',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.CurrencyBalance',
      '10': 'balances'
    },
  ],
  '9': [
    {'1': 3, '2': 4},
  ],
  '10': ['balance_minor'],
};

/// Descriptor for `UpdateAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateAccountRequestDescriptor = $convert.base64Decode(
    'ChRVcGRhdGVBY2NvdW50UmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEisKBHR5cGUYAiABKA'
    '4yFy5wcnVkZW50LnYxLkFjY291bnRUeXBlUgR0eXBlEh0KCmlzX2RlZmF1bHQYBCABKAhSCWlz'
    'RGVmYXVsdBIbCglpc19hY3RpdmUYBSABKAhSCGlzQWN0aXZlEigKEGluY2x1ZGVfaW5fdG90YW'
    'wYBiABKAhSDmluY2x1ZGVJblRvdGFsEi4KE2luY2x1ZGVfaW5fb3ZlcnZpZXcYByABKAhSEWlu'
    'Y2x1ZGVJbk92ZXJ2aWV3EjcKCGJhbGFuY2VzGAggAygLMhsucHJ1ZGVudC52MS5DdXJyZW5jeU'
    'JhbGFuY2VSCGJhbGFuY2VzSgQIAxAEUg1iYWxhbmNlX21pbm9y');

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
