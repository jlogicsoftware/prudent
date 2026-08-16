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
    {'1': 'category_id', '3': 6, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'account_id', '3': 7, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `Record`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordDescriptor = $convert.base64Decode(
    'CgZSZWNvcmQSDgoCaWQYASABKAlSAmlkEhQKBXRpdGxlGAIgASgJUgV0aXRsZRIhCgxhbW91bn'
    'RfbWlub3IYAyABKANSC2Ftb3VudE1pbm9yEhoKCGN1cnJlbmN5GAQgASgJUghjdXJyZW5jeRIS'
    'CgRkYXRlGAUgASgJUgRkYXRlEh8KC2NhdGVnb3J5X2lkGAYgASgJUgpjYXRlZ29yeUlkEh0KCm'
    'FjY291bnRfaWQYByABKAlSCWFjY291bnRJZA==');

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
