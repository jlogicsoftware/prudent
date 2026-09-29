// This is a generated file - do not edit.
//
// Generated from prudent/v1/budgets.proto.

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

@$core.Deprecated('Use budgetDescriptor instead')
const Budget$json = {
  '1': 'Budget',
  '2': [
    {'1': 'category_id', '3': 1, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'month', '3': 2, '4': 1, '5': 9, '10': 'month'},
    {'1': 'currency', '3': 3, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 4, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `Budget`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List budgetDescriptor = $convert.base64Decode(
    'CgZCdWRnZXQSHwoLY2F0ZWdvcnlfaWQYASABKAlSCmNhdGVnb3J5SWQSFAoFbW9udGgYAiABKA'
    'lSBW1vbnRoEhoKCGN1cnJlbmN5GAMgASgJUghjdXJyZW5jeRIhCgxhbW91bnRfbWlub3IYBCAB'
    'KANSC2Ftb3VudE1pbm9y');

@$core.Deprecated('Use setBudgetRequestDescriptor instead')
const SetBudgetRequest$json = {
  '1': 'SetBudgetRequest',
  '2': [
    {'1': 'amount_minor', '3': 1, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `SetBudgetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setBudgetRequestDescriptor = $convert.base64Decode(
    'ChBTZXRCdWRnZXRSZXF1ZXN0EiEKDGFtb3VudF9taW5vchgBIAEoA1ILYW1vdW50TWlub3I=');

@$core.Deprecated('Use listBudgetsResponseDescriptor instead')
const ListBudgetsResponse$json = {
  '1': 'ListBudgetsResponse',
  '2': [
    {
      '1': 'budgets',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Budget',
      '10': 'budgets'
    },
  ],
};

/// Descriptor for `ListBudgetsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listBudgetsResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0QnVkZ2V0c1Jlc3BvbnNlEiwKB2J1ZGdldHMYASADKAsyEi5wcnVkZW50LnYxLkJ1ZG'
    'dldFIHYnVkZ2V0cw==');
