// This is a generated file - do not edit.
//
// Generated from prudent/v1/reminders.proto.

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

@$core.Deprecated('Use dueReminderDescriptor instead')
const DueReminder$json = {
  '1': 'DueReminder',
  '2': [
    {
      '1': 'occurrence',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.PlanOccurrence',
      '10': 'occurrence'
    },
    {'1': 'remind_on', '3': 2, '4': 1, '5': 9, '10': 'remindOn'},
    {'1': 'lead_days', '3': 3, '4': 1, '5': 13, '10': 'leadDays'},
    {'1': 'read', '3': 4, '4': 1, '5': 8, '10': 'read'},
  ],
};

/// Descriptor for `DueReminder`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dueReminderDescriptor = $convert.base64Decode(
    'CgtEdWVSZW1pbmRlchI6CgpvY2N1cnJlbmNlGAEgASgLMhoucHJ1ZGVudC52MS5QbGFuT2NjdX'
    'JyZW5jZVIKb2NjdXJyZW5jZRIbCglyZW1pbmRfb24YAiABKAlSCHJlbWluZE9uEhsKCWxlYWRf'
    'ZGF5cxgDIAEoDVIIbGVhZERheXMSEgoEcmVhZBgEIAEoCFIEcmVhZA==');

@$core.Deprecated('Use listRemindersResponseDescriptor instead')
const ListRemindersResponse$json = {
  '1': 'ListRemindersResponse',
  '2': [
    {
      '1': 'reminders',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.DueReminder',
      '10': 'reminders'
    },
  ],
};

/// Descriptor for `ListRemindersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listRemindersResponseDescriptor = $convert.base64Decode(
    'ChVMaXN0UmVtaW5kZXJzUmVzcG9uc2USNQoJcmVtaW5kZXJzGAEgAygLMhcucHJ1ZGVudC52MS'
    '5EdWVSZW1pbmRlclIJcmVtaW5kZXJz');
