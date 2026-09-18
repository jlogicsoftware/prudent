// This is a generated file - do not edit.
//
// Generated from prudent/v1/records.proto.

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

@$core.Deprecated('Use recordDescriptor instead')
const Record$json = {
  '1': 'Record',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 3, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'currency', '3': 4, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'date', '3': 5, '4': 1, '5': 9, '10': 'date'},
    {
      '1': 'category_id',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'categoryId',
      '17': true
    },
    {'1': 'account_id', '3': 7, '4': 1, '5': 9, '10': 'accountId'},
    {
      '1': 'transfer_id',
      '3': 8,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'transferId',
      '17': true
    },
  ],
  '8': [
    {'1': '_category_id'},
    {'1': '_transfer_id'},
  ],
};

/// Descriptor for `Record`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordDescriptor = $convert.base64Decode(
    'CgZSZWNvcmQSDgoCaWQYASABKAlSAmlkEhQKBXRpdGxlGAIgASgJUgV0aXRsZRIhCgxhbW91bn'
    'RfbWlub3IYAyABKANSC2Ftb3VudE1pbm9yEhoKCGN1cnJlbmN5GAQgASgJUghjdXJyZW5jeRIS'
    'CgRkYXRlGAUgASgJUgRkYXRlEiQKC2NhdGVnb3J5X2lkGAYgASgJSABSCmNhdGVnb3J5SWSIAQ'
    'ESHQoKYWNjb3VudF9pZBgHIAEoCVIJYWNjb3VudElkEiQKC3RyYW5zZmVyX2lkGAggASgJSAFS'
    'CnRyYW5zZmVySWSIAQFCDgoMX2NhdGVnb3J5X2lkQg4KDF90cmFuc2Zlcl9pZA==');

@$core.Deprecated('Use createRecordRequestDescriptor instead')
const CreateRecordRequest$json = {
  '1': 'CreateRecordRequest',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'date', '3': 3, '4': 1, '5': 9, '10': 'date'},
    {'1': 'category_id', '3': 4, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'account_id', '3': 5, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'currency', '3': 6, '4': 1, '5': 9, '10': 'currency'},
  ],
};

/// Descriptor for `CreateRecordRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createRecordRequestDescriptor = $convert.base64Decode(
    'ChNDcmVhdGVSZWNvcmRSZXF1ZXN0EhQKBXRpdGxlGAEgASgJUgV0aXRsZRIhCgxhbW91bnRfbW'
    'lub3IYAiABKANSC2Ftb3VudE1pbm9yEhIKBGRhdGUYAyABKAlSBGRhdGUSHwoLY2F0ZWdvcnlf'
    'aWQYBCABKAlSCmNhdGVnb3J5SWQSHQoKYWNjb3VudF9pZBgFIAEoCVIJYWNjb3VudElkEhoKCG'
    'N1cnJlbmN5GAYgASgJUghjdXJyZW5jeQ==');

@$core.Deprecated('Use updateRecordRequestDescriptor instead')
const UpdateRecordRequest$json = {
  '1': 'UpdateRecordRequest',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'date', '3': 3, '4': 1, '5': 9, '10': 'date'},
    {'1': 'category_id', '3': 4, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'account_id', '3': 5, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'currency', '3': 6, '4': 1, '5': 9, '10': 'currency'},
  ],
};

/// Descriptor for `UpdateRecordRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateRecordRequestDescriptor = $convert.base64Decode(
    'ChNVcGRhdGVSZWNvcmRSZXF1ZXN0EhQKBXRpdGxlGAEgASgJUgV0aXRsZRIhCgxhbW91bnRfbW'
    'lub3IYAiABKANSC2Ftb3VudE1pbm9yEhIKBGRhdGUYAyABKAlSBGRhdGUSHwoLY2F0ZWdvcnlf'
    'aWQYBCABKAlSCmNhdGVnb3J5SWQSHQoKYWNjb3VudF9pZBgFIAEoCVIJYWNjb3VudElkEhoKCG'
    'N1cnJlbmN5GAYgASgJUghjdXJyZW5jeQ==');

@$core.Deprecated('Use listRecordsResponseDescriptor instead')
const ListRecordsResponse$json = {
  '1': 'ListRecordsResponse',
  '2': [
    {
      '1': 'records',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Record',
      '10': 'records'
    },
  ],
};

/// Descriptor for `ListRecordsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRecordsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0UmVjb3Jkc1Jlc3BvbnNlEiwKB3JlY29yZHMYASADKAsyEi5wcnVkZW50LnYxLlJlY2'
    '9yZFIHcmVjb3Jkcw==');

@$core.Deprecated('Use createTransferRequestDescriptor instead')
const CreateTransferRequest$json = {
  '1': 'CreateTransferRequest',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'from_amount_minor', '3': 2, '4': 1, '5': 3, '10': 'fromAmountMinor'},
    {'1': 'from_currency', '3': 3, '4': 1, '5': 9, '10': 'fromCurrency'},
    {'1': 'date', '3': 4, '4': 1, '5': 9, '10': 'date'},
    {'1': 'from_account_id', '3': 5, '4': 1, '5': 9, '10': 'fromAccountId'},
    {'1': 'to_account_id', '3': 6, '4': 1, '5': 9, '10': 'toAccountId'},
    {'1': 'to_amount_minor', '3': 7, '4': 1, '5': 3, '10': 'toAmountMinor'},
    {'1': 'to_currency', '3': 8, '4': 1, '5': 9, '10': 'toCurrency'},
  ],
};

/// Descriptor for `CreateTransferRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createTransferRequestDescriptor = $convert.base64Decode(
    'ChVDcmVhdGVUcmFuc2ZlclJlcXVlc3QSFAoFdGl0bGUYASABKAlSBXRpdGxlEioKEWZyb21fYW'
    '1vdW50X21pbm9yGAIgASgDUg9mcm9tQW1vdW50TWlub3ISIwoNZnJvbV9jdXJyZW5jeRgDIAEo'
    'CVIMZnJvbUN1cnJlbmN5EhIKBGRhdGUYBCABKAlSBGRhdGUSJgoPZnJvbV9hY2NvdW50X2lkGA'
    'UgASgJUg1mcm9tQWNjb3VudElkEiIKDXRvX2FjY291bnRfaWQYBiABKAlSC3RvQWNjb3VudElk'
    'EiYKD3RvX2Ftb3VudF9taW5vchgHIAEoA1INdG9BbW91bnRNaW5vchIfCgt0b19jdXJyZW5jeR'
    'gIIAEoCVIKdG9DdXJyZW5jeQ==');

@$core.Deprecated('Use transferDescriptor instead')
const Transfer$json = {
  '1': 'Transfer',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'from_record',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Record',
      '10': 'fromRecord'
    },
    {
      '1': 'to_record',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Record',
      '10': 'toRecord'
    },
  ],
};

/// Descriptor for `Transfer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferDescriptor = $convert.base64Decode(
    'CghUcmFuc2ZlchIOCgJpZBgBIAEoCVICaWQSMwoLZnJvbV9yZWNvcmQYAiABKAsyEi5wcnVkZW'
    '50LnYxLlJlY29yZFIKZnJvbVJlY29yZBIvCgl0b19yZWNvcmQYAyABKAsyEi5wcnVkZW50LnYx'
    'LlJlY29yZFIIdG9SZWNvcmQ=');
