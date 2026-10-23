// This is a generated file - do not edit.
//
// Generated from prudent/v1/privacy.proto.

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

@$core.Deprecated('Use exportProfileDescriptor instead')
const ExportProfile$json = {
  '1': 'ExportProfile',
  '2': [
    {'1': 'email', '3': 1, '4': 1, '5': 9, '10': 'email'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'nickname', '3': 3, '4': 1, '5': 9, '10': 'nickname'},
    {'1': 'language', '3': 4, '4': 1, '5': 9, '10': 'language'},
    {'1': 'created_at_ms', '3': 5, '4': 1, '5': 3, '10': 'createdAtMs'},
  ],
};

/// Descriptor for `ExportProfile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List exportProfileDescriptor = $convert.base64Decode(
    'Cg1FeHBvcnRQcm9maWxlEhQKBWVtYWlsGAEgASgJUgVlbWFpbBIhCgxkaXNwbGF5X25hbWUYAi'
    'ABKAlSC2Rpc3BsYXlOYW1lEhoKCG5pY2tuYW1lGAMgASgJUghuaWNrbmFtZRIaCghsYW5ndWFn'
    'ZRgEIAEoCVIIbGFuZ3VhZ2USIgoNY3JlYXRlZF9hdF9tcxgFIAEoA1ILY3JlYXRlZEF0TXM=');

@$core.Deprecated('Use dataExportDescriptor instead')
const DataExport$json = {
  '1': 'DataExport',
  '2': [
    {'1': 'format_version', '3': 1, '4': 1, '5': 5, '10': 'formatVersion'},
    {'1': 'exported_at_ms', '3': 2, '4': 1, '5': 3, '10': 'exportedAtMs'},
    {
      '1': 'profile',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.ExportProfile',
      '10': 'profile'
    },
    {
      '1': 'settings',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Settings',
      '10': 'settings'
    },
    {
      '1': 'accounts',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Account',
      '10': 'accounts'
    },
    {
      '1': 'categories',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Category',
      '10': 'categories'
    },
    {
      '1': 'records',
      '3': 7,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Record',
      '10': 'records'
    },
    {
      '1': 'plans',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Plan',
      '10': 'plans'
    },
    {
      '1': 'occurrences',
      '3': 9,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.PlanOccurrence',
      '10': 'occurrences'
    },
    {
      '1': 'budgets',
      '3': 10,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Budget',
      '10': 'budgets'
    },
    {
      '1': 'carry_over_resets',
      '3': 11,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.BudgetCarryOverReset',
      '10': 'carryOverResets'
    },
    {
      '1': 'goals',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Goal',
      '10': 'goals'
    },
    {
      '1': 'goal_allocations',
      '3': 13,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.GoalAllocation',
      '10': 'goalAllocations'
    },
  ],
};

/// Descriptor for `DataExport`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dataExportDescriptor = $convert.base64Decode(
    'CgpEYXRhRXhwb3J0EiUKDmZvcm1hdF92ZXJzaW9uGAEgASgFUg1mb3JtYXRWZXJzaW9uEiQKDm'
    'V4cG9ydGVkX2F0X21zGAIgASgDUgxleHBvcnRlZEF0TXMSMwoHcHJvZmlsZRgDIAEoCzIZLnBy'
    'dWRlbnQudjEuRXhwb3J0UHJvZmlsZVIHcHJvZmlsZRIwCghzZXR0aW5ncxgEIAEoCzIULnBydW'
    'RlbnQudjEuU2V0dGluZ3NSCHNldHRpbmdzEi8KCGFjY291bnRzGAUgAygLMhMucHJ1ZGVudC52'
    'MS5BY2NvdW50UghhY2NvdW50cxI0CgpjYXRlZ29yaWVzGAYgAygLMhQucHJ1ZGVudC52MS5DYX'
    'RlZ29yeVIKY2F0ZWdvcmllcxIsCgdyZWNvcmRzGAcgAygLMhIucHJ1ZGVudC52MS5SZWNvcmRS'
    'B3JlY29yZHMSJgoFcGxhbnMYCCADKAsyEC5wcnVkZW50LnYxLlBsYW5SBXBsYW5zEjwKC29jY3'
    'VycmVuY2VzGAkgAygLMhoucHJ1ZGVudC52MS5QbGFuT2NjdXJyZW5jZVILb2NjdXJyZW5jZXMS'
    'LAoHYnVkZ2V0cxgKIAMoCzISLnBydWRlbnQudjEuQnVkZ2V0UgdidWRnZXRzEkwKEWNhcnJ5X2'
    '92ZXJfcmVzZXRzGAsgAygLMiAucHJ1ZGVudC52MS5CdWRnZXRDYXJyeU92ZXJSZXNldFIPY2Fy'
    'cnlPdmVyUmVzZXRzEiYKBWdvYWxzGAwgAygLMhAucHJ1ZGVudC52MS5Hb2FsUgVnb2FscxJFCh'
    'Bnb2FsX2FsbG9jYXRpb25zGA0gAygLMhoucHJ1ZGVudC52MS5Hb2FsQWxsb2NhdGlvblIPZ29h'
    'bEFsbG9jYXRpb25z');

@$core.Deprecated('Use eraseAccountRequestDescriptor instead')
const EraseAccountRequest$json = {
  '1': 'EraseAccountRequest',
  '2': [
    {'1': 'confirm_email', '3': 1, '4': 1, '5': 9, '10': 'confirmEmail'},
  ],
};

/// Descriptor for `EraseAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List eraseAccountRequestDescriptor = $convert.base64Decode(
    'ChNFcmFzZUFjY291bnRSZXF1ZXN0EiMKDWNvbmZpcm1fZW1haWwYASABKAlSDGNvbmZpcm1FbW'
    'FpbA==');
