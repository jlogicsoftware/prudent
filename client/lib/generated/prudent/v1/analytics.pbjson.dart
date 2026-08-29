// This is a generated file - do not edit.
//
// Generated from prudent/v1/analytics.proto.

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

@$core.Deprecated('Use granularityDescriptor instead')
const Granularity$json = {
  '1': 'Granularity',
  '2': [
    {'1': 'GRANULARITY_UNSPECIFIED', '2': 0},
    {'1': 'GRANULARITY_MONTH', '2': 1},
    {'1': 'GRANULARITY_YEAR', '2': 2},
  ],
};

/// Descriptor for `Granularity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List granularityDescriptor = $convert.base64Decode(
    'CgtHcmFudWxhcml0eRIbChdHUkFOVUxBUklUWV9VTlNQRUNJRklFRBAAEhUKEUdSQU5VTEFSSV'
    'RZX01PTlRIEAESFAoQR1JBTlVMQVJJVFlfWUVBUhAC');

@$core.Deprecated('Use categorySpendDescriptor instead')
const CategorySpend$json = {
  '1': 'CategorySpend',
  '2': [
    {'1': 'category_id', '3': 1, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `CategorySpend`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categorySpendDescriptor = $convert.base64Decode(
    'Cg1DYXRlZ29yeVNwZW5kEh8KC2NhdGVnb3J5X2lkGAEgASgJUgpjYXRlZ29yeUlkEiEKDGFtb3'
    'VudF9taW5vchgCIAEoA1ILYW1vdW50TWlub3I=');

@$core.Deprecated('Use spendByCategoryResponseDescriptor instead')
const SpendByCategoryResponse$json = {
  '1': 'SpendByCategoryResponse',
  '2': [
    {'1': 'currency', '3': 1, '4': 1, '5': 9, '10': 'currency'},
    {
      '1': 'items',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.CategorySpend',
      '10': 'items'
    },
  ],
};

/// Descriptor for `SpendByCategoryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spendByCategoryResponseDescriptor =
    $convert.base64Decode(
        'ChdTcGVuZEJ5Q2F0ZWdvcnlSZXNwb25zZRIaCghjdXJyZW5jeRgBIAEoCVIIY3VycmVuY3kSLw'
        'oFaXRlbXMYAiADKAsyGS5wcnVkZW50LnYxLkNhdGVnb3J5U3BlbmRSBWl0ZW1z');

@$core.Deprecated('Use periodSpendDescriptor instead')
const PeriodSpend$json = {
  '1': 'PeriodSpend',
  '2': [
    {'1': 'period', '3': 1, '4': 1, '5': 9, '10': 'period'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `PeriodSpend`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List periodSpendDescriptor = $convert.base64Decode(
    'CgtQZXJpb2RTcGVuZBIWCgZwZXJpb2QYASABKAlSBnBlcmlvZBIhCgxhbW91bnRfbWlub3IYAi'
    'ABKANSC2Ftb3VudE1pbm9y');

@$core.Deprecated('Use spendByPeriodResponseDescriptor instead')
const SpendByPeriodResponse$json = {
  '1': 'SpendByPeriodResponse',
  '2': [
    {'1': 'currency', '3': 1, '4': 1, '5': 9, '10': 'currency'},
    {
      '1': 'granularity',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.Granularity',
      '10': 'granularity'
    },
    {
      '1': 'periods',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.PeriodSpend',
      '10': 'periods'
    },
  ],
};

/// Descriptor for `SpendByPeriodResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List spendByPeriodResponseDescriptor = $convert.base64Decode(
    'ChVTcGVuZEJ5UGVyaW9kUmVzcG9uc2USGgoIY3VycmVuY3kYASABKAlSCGN1cnJlbmN5EjkKC2'
    'dyYW51bGFyaXR5GAIgASgOMhcucHJ1ZGVudC52MS5HcmFudWxhcml0eVILZ3JhbnVsYXJpdHkS'
    'MQoHcGVyaW9kcxgDIAMoCzIXLnBydWRlbnQudjEuUGVyaW9kU3BlbmRSB3BlcmlvZHM=');
