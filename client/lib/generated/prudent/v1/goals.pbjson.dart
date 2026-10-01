// This is a generated file - do not edit.
//
// Generated from prudent/v1/goals.proto.

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

@$core.Deprecated('Use goalStatusDescriptor instead')
const GoalStatus$json = {
  '1': 'GoalStatus',
  '2': [
    {'1': 'GOAL_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'GOAL_STATUS_ACTIVE', '2': 1},
    {'1': 'GOAL_STATUS_COMPLETED', '2': 2},
    {'1': 'GOAL_STATUS_ARCHIVED', '2': 3},
  ],
};

/// Descriptor for `GoalStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List goalStatusDescriptor = $convert.base64Decode(
    'CgpHb2FsU3RhdHVzEhsKF0dPQUxfU1RBVFVTX1VOU1BFQ0lGSUVEEAASFgoSR09BTF9TVEFUVV'
    'NfQUNUSVZFEAESGQoVR09BTF9TVEFUVVNfQ09NUExFVEVEEAISGAoUR09BTF9TVEFUVVNfQVJD'
    'SElWRUQQAw==');

@$core.Deprecated('Use goalDescriptor instead')
const Goal$json = {
  '1': 'Goal',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'currency', '3': 3, '4': 1, '5': 9, '10': 'currency'},
    {
      '1': 'target_amount_minor',
      '3': 4,
      '4': 1,
      '5': 3,
      '10': 'targetAmountMinor'
    },
    {
      '1': 'target_date',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'targetDate',
      '17': true
    },
    {
      '1': 'status',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.GoalStatus',
      '10': 'status'
    },
    {'1': 'created_at_ms', '3': 7, '4': 1, '5': 3, '10': 'createdAtMs'},
    {
      '1': 'status_changed_at_ms',
      '3': 8,
      '4': 1,
      '5': 3,
      '10': 'statusChangedAtMs'
    },
  ],
  '8': [
    {'1': '_target_date'},
  ],
};

/// Descriptor for `Goal`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List goalDescriptor = $convert.base64Decode(
    'CgRHb2FsEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEhoKCGN1cnJlbmN5GA'
    'MgASgJUghjdXJyZW5jeRIuChN0YXJnZXRfYW1vdW50X21pbm9yGAQgASgDUhF0YXJnZXRBbW91'
    'bnRNaW5vchIkCgt0YXJnZXRfZGF0ZRgFIAEoCUgAUgp0YXJnZXREYXRliAEBEi4KBnN0YXR1cx'
    'gGIAEoDjIWLnBydWRlbnQudjEuR29hbFN0YXR1c1IGc3RhdHVzEiIKDWNyZWF0ZWRfYXRfbXMY'
    'ByABKANSC2NyZWF0ZWRBdE1zEi8KFHN0YXR1c19jaGFuZ2VkX2F0X21zGAggASgDUhFzdGF0dX'
    'NDaGFuZ2VkQXRNc0IOCgxfdGFyZ2V0X2RhdGU=');

@$core.Deprecated('Use createGoalRequestDescriptor instead')
const CreateGoalRequest$json = {
  '1': 'CreateGoalRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'currency', '3': 2, '4': 1, '5': 9, '10': 'currency'},
    {
      '1': 'target_amount_minor',
      '3': 3,
      '4': 1,
      '5': 3,
      '10': 'targetAmountMinor'
    },
    {
      '1': 'target_date',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'targetDate',
      '17': true
    },
  ],
  '8': [
    {'1': '_target_date'},
  ],
};

/// Descriptor for `CreateGoalRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createGoalRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVHb2FsUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEhoKCGN1cnJlbmN5GAIgAS'
    'gJUghjdXJyZW5jeRIuChN0YXJnZXRfYW1vdW50X21pbm9yGAMgASgDUhF0YXJnZXRBbW91bnRN'
    'aW5vchIkCgt0YXJnZXRfZGF0ZRgEIAEoCUgAUgp0YXJnZXREYXRliAEBQg4KDF90YXJnZXRfZG'
    'F0ZQ==');

@$core.Deprecated('Use updateGoalRequestDescriptor instead')
const UpdateGoalRequest$json = {
  '1': 'UpdateGoalRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'target_amount_minor',
      '3': 2,
      '4': 1,
      '5': 3,
      '10': 'targetAmountMinor'
    },
    {
      '1': 'target_date',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'targetDate',
      '17': true
    },
  ],
  '8': [
    {'1': '_target_date'},
  ],
};

/// Descriptor for `UpdateGoalRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateGoalRequestDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVHb2FsUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEi4KE3RhcmdldF9hbW91bn'
    'RfbWlub3IYAiABKANSEXRhcmdldEFtb3VudE1pbm9yEiQKC3RhcmdldF9kYXRlGAMgASgJSABS'
    'CnRhcmdldERhdGWIAQFCDgoMX3RhcmdldF9kYXRl');

@$core.Deprecated('Use listGoalsResponseDescriptor instead')
const ListGoalsResponse$json = {
  '1': 'ListGoalsResponse',
  '2': [
    {
      '1': 'goals',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Goal',
      '10': 'goals'
    },
  ],
};

/// Descriptor for `ListGoalsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listGoalsResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0R29hbHNSZXNwb25zZRImCgVnb2FscxgBIAMoCzIQLnBydWRlbnQudjEuR29hbFIFZ2'
    '9hbHM=');
