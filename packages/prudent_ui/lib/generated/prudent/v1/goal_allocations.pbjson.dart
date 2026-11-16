// This is a generated file - do not edit.
//
// Generated from prudent/v1/goal_allocations.proto.

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

@$core.Deprecated('Use goalAllocationKindDescriptor instead')
const GoalAllocationKind$json = {
  '1': 'GoalAllocationKind',
  '2': [
    {'1': 'GOAL_ALLOCATION_KIND_UNSPECIFIED', '2': 0},
    {'1': 'GOAL_ALLOCATION_KIND_ALLOCATE', '2': 1},
    {'1': 'GOAL_ALLOCATION_KIND_WITHDRAW', '2': 2},
    {'1': 'GOAL_ALLOCATION_KIND_MOVE', '2': 3},
  ],
};

/// Descriptor for `GoalAllocationKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List goalAllocationKindDescriptor = $convert.base64Decode(
    'ChJHb2FsQWxsb2NhdGlvbktpbmQSJAogR09BTF9BTExPQ0FUSU9OX0tJTkRfVU5TUEVDSUZJRU'
    'QQABIhCh1HT0FMX0FMTE9DQVRJT05fS0lORF9BTExPQ0FURRABEiEKHUdPQUxfQUxMT0NBVElP'
    'Tl9LSU5EX1dJVEhEUkFXEAISHQoZR09BTF9BTExPQ0FUSU9OX0tJTkRfTU9WRRAD');

@$core.Deprecated('Use goalAllocationDescriptor instead')
const GoalAllocation$json = {
  '1': 'GoalAllocation',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.GoalAllocationKind',
      '10': 'kind'
    },
    {
      '1': 'source_goal_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'sourceGoalId',
      '17': true
    },
    {
      '1': 'target_goal_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'targetGoalId',
      '17': true
    },
    {'1': 'currency', '3': 5, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 6, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'note', '3': 7, '4': 1, '5': 9, '10': 'note'},
    {'1': 'created_at_ms', '3': 8, '4': 1, '5': 3, '10': 'createdAtMs'},
    {'1': 'created_by', '3': 9, '4': 1, '5': 9, '10': 'createdBy'},
  ],
  '8': [
    {'1': '_source_goal_id'},
    {'1': '_target_goal_id'},
  ],
};

/// Descriptor for `GoalAllocation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List goalAllocationDescriptor = $convert.base64Decode(
    'Cg5Hb2FsQWxsb2NhdGlvbhIOCgJpZBgBIAEoCVICaWQSMgoEa2luZBgCIAEoDjIeLnBydWRlbn'
    'QudjEuR29hbEFsbG9jYXRpb25LaW5kUgRraW5kEikKDnNvdXJjZV9nb2FsX2lkGAMgASgJSABS'
    'DHNvdXJjZUdvYWxJZIgBARIpCg50YXJnZXRfZ29hbF9pZBgEIAEoCUgBUgx0YXJnZXRHb2FsSW'
    'SIAQESGgoIY3VycmVuY3kYBSABKAlSCGN1cnJlbmN5EiEKDGFtb3VudF9taW5vchgGIAEoA1IL'
    'YW1vdW50TWlub3ISEgoEbm90ZRgHIAEoCVIEbm90ZRIiCg1jcmVhdGVkX2F0X21zGAggASgDUg'
    'tjcmVhdGVkQXRNcxIdCgpjcmVhdGVkX2J5GAkgASgJUgljcmVhdGVkQnlCEQoPX3NvdXJjZV9n'
    'b2FsX2lkQhEKD190YXJnZXRfZ29hbF9pZA==');

@$core.Deprecated('Use createGoalAllocationRequestDescriptor instead')
const CreateGoalAllocationRequest$json = {
  '1': 'CreateGoalAllocationRequest',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.GoalAllocationKind',
      '10': 'kind'
    },
    {
      '1': 'source_goal_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'sourceGoalId',
      '17': true
    },
    {
      '1': 'target_goal_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'targetGoalId',
      '17': true
    },
    {'1': 'amount_minor', '3': 4, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'note', '3': 5, '4': 1, '5': 9, '10': 'note'},
  ],
  '8': [
    {'1': '_source_goal_id'},
    {'1': '_target_goal_id'},
  ],
};

/// Descriptor for `CreateGoalAllocationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createGoalAllocationRequestDescriptor = $convert.base64Decode(
    'ChtDcmVhdGVHb2FsQWxsb2NhdGlvblJlcXVlc3QSMgoEa2luZBgBIAEoDjIeLnBydWRlbnQudj'
    'EuR29hbEFsbG9jYXRpb25LaW5kUgRraW5kEikKDnNvdXJjZV9nb2FsX2lkGAIgASgJSABSDHNv'
    'dXJjZUdvYWxJZIgBARIpCg50YXJnZXRfZ29hbF9pZBgDIAEoCUgBUgx0YXJnZXRHb2FsSWSIAQ'
    'ESIQoMYW1vdW50X21pbm9yGAQgASgDUgthbW91bnRNaW5vchISCgRub3RlGAUgASgJUgRub3Rl'
    'QhEKD19zb3VyY2VfZ29hbF9pZEIRCg9fdGFyZ2V0X2dvYWxfaWQ=');

@$core.Deprecated('Use listGoalAllocationsResponseDescriptor instead')
const ListGoalAllocationsResponse$json = {
  '1': 'ListGoalAllocationsResponse',
  '2': [
    {
      '1': 'allocations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.GoalAllocation',
      '10': 'allocations'
    },
  ],
};

/// Descriptor for `ListGoalAllocationsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listGoalAllocationsResponseDescriptor =
    $convert.base64Decode(
        'ChtMaXN0R29hbEFsbG9jYXRpb25zUmVzcG9uc2USPAoLYWxsb2NhdGlvbnMYASADKAsyGi5wcn'
        'VkZW50LnYxLkdvYWxBbGxvY2F0aW9uUgthbGxvY2F0aW9ucw==');

@$core.Deprecated('Use goalEnvelopeDescriptor instead')
const GoalEnvelope$json = {
  '1': 'GoalEnvelope',
  '2': [
    {'1': 'goal_id', '3': 1, '4': 1, '5': 9, '10': 'goalId'},
    {'1': 'currency', '3': 2, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 3, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `GoalEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List goalEnvelopeDescriptor = $convert.base64Decode(
    'CgxHb2FsRW52ZWxvcGUSFwoHZ29hbF9pZBgBIAEoCVIGZ29hbElkEhoKCGN1cnJlbmN5GAIgAS'
    'gJUghjdXJyZW5jeRIhCgxhbW91bnRfbWlub3IYAyABKANSC2Ftb3VudE1pbm9y');

@$core.Deprecated('Use listGoalEnvelopesResponseDescriptor instead')
const ListGoalEnvelopesResponse$json = {
  '1': 'ListGoalEnvelopesResponse',
  '2': [
    {
      '1': 'envelopes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.GoalEnvelope',
      '10': 'envelopes'
    },
  ],
};

/// Descriptor for `ListGoalEnvelopesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listGoalEnvelopesResponseDescriptor =
    $convert.base64Decode(
        'ChlMaXN0R29hbEVudmVsb3Blc1Jlc3BvbnNlEjYKCWVudmVsb3BlcxgBIAMoCzIYLnBydWRlbn'
        'QudjEuR29hbEVudmVsb3BlUgllbnZlbG9wZXM=');

@$core.Deprecated('Use currencyFreeMoneyDescriptor instead')
const CurrencyFreeMoney$json = {
  '1': 'CurrencyFreeMoney',
  '2': [
    {'1': 'currency', '3': 1, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'eligible_minor', '3': 2, '4': 1, '5': 3, '10': 'eligibleMinor'},
    {'1': 'allocated_minor', '3': 3, '4': 1, '5': 3, '10': 'allocatedMinor'},
    {'1': 'free_minor', '3': 4, '4': 1, '5': 3, '10': 'freeMinor'},
    {
      '1': 'eligible_account_ids',
      '3': 5,
      '4': 3,
      '5': 9,
      '10': 'eligibleAccountIds'
    },
  ],
};

/// Descriptor for `CurrencyFreeMoney`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List currencyFreeMoneyDescriptor = $convert.base64Decode(
    'ChFDdXJyZW5jeUZyZWVNb25leRIaCghjdXJyZW5jeRgBIAEoCVIIY3VycmVuY3kSJQoOZWxpZ2'
    'libGVfbWlub3IYAiABKANSDWVsaWdpYmxlTWlub3ISJwoPYWxsb2NhdGVkX21pbm9yGAMgASgD'
    'Ug5hbGxvY2F0ZWRNaW5vchIdCgpmcmVlX21pbm9yGAQgASgDUglmcmVlTWlub3ISMAoUZWxpZ2'
    'libGVfYWNjb3VudF9pZHMYBSADKAlSEmVsaWdpYmxlQWNjb3VudElkcw==');

@$core.Deprecated('Use getFreeMoneyResponseDescriptor instead')
const GetFreeMoneyResponse$json = {
  '1': 'GetFreeMoneyResponse',
  '2': [
    {
      '1': 'currencies',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.CurrencyFreeMoney',
      '10': 'currencies'
    },
  ],
};

/// Descriptor for `GetFreeMoneyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFreeMoneyResponseDescriptor = $convert.base64Decode(
    'ChRHZXRGcmVlTW9uZXlSZXNwb25zZRI9CgpjdXJyZW5jaWVzGAEgAygLMh0ucHJ1ZGVudC52MS'
    '5DdXJyZW5jeUZyZWVNb25leVIKY3VycmVuY2llcw==');
