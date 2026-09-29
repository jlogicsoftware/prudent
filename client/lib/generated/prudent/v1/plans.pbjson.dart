// This is a generated file - do not edit.
//
// Generated from prudent/v1/plans.proto.

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

@$core.Deprecated('Use recurrenceFrequencyDescriptor instead')
const RecurrenceFrequency$json = {
  '1': 'RecurrenceFrequency',
  '2': [
    {'1': 'RECURRENCE_FREQUENCY_UNSPECIFIED', '2': 0},
    {'1': 'RECURRENCE_FREQUENCY_ONCE', '2': 1},
    {'1': 'RECURRENCE_FREQUENCY_DAILY', '2': 2},
    {'1': 'RECURRENCE_FREQUENCY_WEEKLY', '2': 3},
    {'1': 'RECURRENCE_FREQUENCY_MONTHLY', '2': 4},
    {'1': 'RECURRENCE_FREQUENCY_YEARLY', '2': 5},
  ],
};

/// Descriptor for `RecurrenceFrequency`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List recurrenceFrequencyDescriptor = $convert.base64Decode(
    'ChNSZWN1cnJlbmNlRnJlcXVlbmN5EiQKIFJFQ1VSUkVOQ0VfRlJFUVVFTkNZX1VOU1BFQ0lGSU'
    'VEEAASHQoZUkVDVVJSRU5DRV9GUkVRVUVOQ1lfT05DRRABEh4KGlJFQ1VSUkVOQ0VfRlJFUVVF'
    'TkNZX0RBSUxZEAISHwobUkVDVVJSRU5DRV9GUkVRVUVOQ1lfV0VFS0xZEAMSIAocUkVDVVJSRU'
    '5DRV9GUkVRVUVOQ1lfTU9OVEhMWRAEEh8KG1JFQ1VSUkVOQ0VfRlJFUVVFTkNZX1lFQVJMWRAF');

@$core.Deprecated('Use occurrenceStatusDescriptor instead')
const OccurrenceStatus$json = {
  '1': 'OccurrenceStatus',
  '2': [
    {'1': 'OCCURRENCE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'OCCURRENCE_STATUS_PLANNED', '2': 1},
    {'1': 'OCCURRENCE_STATUS_COMPLETED', '2': 2},
    {'1': 'OCCURRENCE_STATUS_SKIPPED', '2': 3},
    {'1': 'OCCURRENCE_STATUS_OVERDUE', '2': 4},
  ],
};

/// Descriptor for `OccurrenceStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List occurrenceStatusDescriptor = $convert.base64Decode(
    'ChBPY2N1cnJlbmNlU3RhdHVzEiEKHU9DQ1VSUkVOQ0VfU1RBVFVTX1VOU1BFQ0lGSUVEEAASHQ'
    'oZT0NDVVJSRU5DRV9TVEFUVVNfUExBTk5FRBABEh8KG09DQ1VSUkVOQ0VfU1RBVFVTX0NPTVBM'
    'RVRFRBACEh0KGU9DQ1VSUkVOQ0VfU1RBVFVTX1NLSVBQRUQQAxIdChlPQ0NVUlJFTkNFX1NUQV'
    'RVU19PVkVSRFVFEAQ=');

@$core.Deprecated('Use recurrenceDescriptor instead')
const Recurrence$json = {
  '1': 'Recurrence',
  '2': [
    {
      '1': 'frequency',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.RecurrenceFrequency',
      '10': 'frequency'
    },
    {'1': 'interval', '3': 2, '4': 1, '5': 13, '10': 'interval'},
    {'1': 'start_date', '3': 3, '4': 1, '5': 9, '10': 'startDate'},
    {'1': 'time_zone', '3': 4, '4': 1, '5': 9, '10': 'timeZone'},
    {'1': 'until_date', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'untilDate'},
    {
      '1': 'occurrence_count',
      '3': 6,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'occurrenceCount'
    },
  ],
  '8': [
    {'1': 'end'},
  ],
};

/// Descriptor for `Recurrence`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recurrenceDescriptor = $convert.base64Decode(
    'CgpSZWN1cnJlbmNlEj0KCWZyZXF1ZW5jeRgBIAEoDjIfLnBydWRlbnQudjEuUmVjdXJyZW5jZU'
    'ZyZXF1ZW5jeVIJZnJlcXVlbmN5EhoKCGludGVydmFsGAIgASgNUghpbnRlcnZhbBIdCgpzdGFy'
    'dF9kYXRlGAMgASgJUglzdGFydERhdGUSGwoJdGltZV96b25lGAQgASgJUgh0aW1lWm9uZRIfCg'
    'p1bnRpbF9kYXRlGAUgASgJSABSCXVudGlsRGF0ZRIrChBvY2N1cnJlbmNlX2NvdW50GAYgASgN'
    'SABSD29jY3VycmVuY2VDb3VudEIFCgNlbmQ=');

@$core.Deprecated('Use planDescriptor instead')
const Plan$json = {
  '1': 'Plan',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 3, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'currency', '3': 4, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'account_id', '3': 5, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'category_id', '3': 6, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'payee', '3': 7, '4': 1, '5': 9, '9': 0, '10': 'payee', '17': true},
    {'1': 'note', '3': 8, '4': 1, '5': 9, '9': 1, '10': 'note', '17': true},
    {
      '1': 'recurrence',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Recurrence',
      '10': 'recurrence'
    },
  ],
  '8': [
    {'1': '_payee'},
    {'1': '_note'},
  ],
};

/// Descriptor for `Plan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planDescriptor = $convert.base64Decode(
    'CgRQbGFuEg4KAmlkGAEgASgJUgJpZBIUCgV0aXRsZRgCIAEoCVIFdGl0bGUSIQoMYW1vdW50X2'
    '1pbm9yGAMgASgDUgthbW91bnRNaW5vchIaCghjdXJyZW5jeRgEIAEoCVIIY3VycmVuY3kSHQoK'
    'YWNjb3VudF9pZBgFIAEoCVIJYWNjb3VudElkEh8KC2NhdGVnb3J5X2lkGAYgASgJUgpjYXRlZ2'
    '9yeUlkEhkKBXBheWVlGAcgASgJSABSBXBheWVliAEBEhcKBG5vdGUYCCABKAlIAVIEbm90ZYgB'
    'ARI2CgpyZWN1cnJlbmNlGAkgASgLMhYucHJ1ZGVudC52MS5SZWN1cnJlbmNlUgpyZWN1cnJlbm'
    'NlQggKBl9wYXllZUIHCgVfbm90ZQ==');

@$core.Deprecated('Use createPlanRequestDescriptor instead')
const CreatePlanRequest$json = {
  '1': 'CreatePlanRequest',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'currency', '3': 3, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'account_id', '3': 4, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'category_id', '3': 5, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'payee', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'payee', '17': true},
    {'1': 'note', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'note', '17': true},
    {
      '1': 'recurrence',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Recurrence',
      '10': 'recurrence'
    },
  ],
  '8': [
    {'1': '_payee'},
    {'1': '_note'},
  ],
};

/// Descriptor for `CreatePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createPlanRequestDescriptor = $convert.base64Decode(
    'ChFDcmVhdGVQbGFuUmVxdWVzdBIUCgV0aXRsZRgBIAEoCVIFdGl0bGUSIQoMYW1vdW50X21pbm'
    '9yGAIgASgDUgthbW91bnRNaW5vchIaCghjdXJyZW5jeRgDIAEoCVIIY3VycmVuY3kSHQoKYWNj'
    'b3VudF9pZBgEIAEoCVIJYWNjb3VudElkEh8KC2NhdGVnb3J5X2lkGAUgASgJUgpjYXRlZ29yeU'
    'lkEhkKBXBheWVlGAYgASgJSABSBXBheWVliAEBEhcKBG5vdGUYByABKAlIAVIEbm90ZYgBARI2'
    'CgpyZWN1cnJlbmNlGAggASgLMhYucHJ1ZGVudC52MS5SZWN1cnJlbmNlUgpyZWN1cnJlbmNlQg'
    'gKBl9wYXllZUIHCgVfbm90ZQ==');

@$core.Deprecated('Use updatePlanRequestDescriptor instead')
const UpdatePlanRequest$json = {
  '1': 'UpdatePlanRequest',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 2, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'currency', '3': 3, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'account_id', '3': 4, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'category_id', '3': 5, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'payee', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'payee', '17': true},
    {'1': 'note', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'note', '17': true},
    {
      '1': 'recurrence',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.prudent.v1.Recurrence',
      '10': 'recurrence'
    },
  ],
  '8': [
    {'1': '_payee'},
    {'1': '_note'},
  ],
};

/// Descriptor for `UpdatePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updatePlanRequestDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVQbGFuUmVxdWVzdBIUCgV0aXRsZRgBIAEoCVIFdGl0bGUSIQoMYW1vdW50X21pbm'
    '9yGAIgASgDUgthbW91bnRNaW5vchIaCghjdXJyZW5jeRgDIAEoCVIIY3VycmVuY3kSHQoKYWNj'
    'b3VudF9pZBgEIAEoCVIJYWNjb3VudElkEh8KC2NhdGVnb3J5X2lkGAUgASgJUgpjYXRlZ29yeU'
    'lkEhkKBXBheWVlGAYgASgJSABSBXBheWVliAEBEhcKBG5vdGUYByABKAlIAVIEbm90ZYgBARI2'
    'CgpyZWN1cnJlbmNlGAggASgLMhYucHJ1ZGVudC52MS5SZWN1cnJlbmNlUgpyZWN1cnJlbmNlQg'
    'gKBl9wYXllZUIHCgVfbm90ZQ==');

@$core.Deprecated('Use listPlansResponseDescriptor instead')
const ListPlansResponse$json = {
  '1': 'ListPlansResponse',
  '2': [
    {
      '1': 'plans',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.Plan',
      '10': 'plans'
    },
  ],
};

/// Descriptor for `ListPlansResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listPlansResponseDescriptor = $convert.base64Decode(
    'ChFMaXN0UGxhbnNSZXNwb25zZRImCgVwbGFucxgBIAMoCzIQLnBydWRlbnQudjEuUGxhblIFcG'
    'xhbnM=');

@$core.Deprecated('Use planOccurrenceDescriptor instead')
const PlanOccurrence$json = {
  '1': 'PlanOccurrence',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'plan_id', '3': 2, '4': 1, '5': 9, '10': 'planId'},
    {'1': 'occurrence_date', '3': 3, '4': 1, '5': 9, '10': 'occurrenceDate'},
    {
      '1': 'status',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.OccurrenceStatus',
      '10': 'status'
    },
    {'1': 'title', '3': 5, '4': 1, '5': 9, '10': 'title'},
    {'1': 'amount_minor', '3': 6, '4': 1, '5': 3, '10': 'amountMinor'},
    {'1': 'currency', '3': 7, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'account_id', '3': 8, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'category_id', '3': 9, '4': 1, '5': 9, '10': 'categoryId'},
  ],
};

/// Descriptor for `PlanOccurrence`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planOccurrenceDescriptor = $convert.base64Decode(
    'Cg5QbGFuT2NjdXJyZW5jZRIOCgJpZBgBIAEoCVICaWQSFwoHcGxhbl9pZBgCIAEoCVIGcGxhbk'
    'lkEicKD29jY3VycmVuY2VfZGF0ZRgDIAEoCVIOb2NjdXJyZW5jZURhdGUSNAoGc3RhdHVzGAQg'
    'ASgOMhwucHJ1ZGVudC52MS5PY2N1cnJlbmNlU3RhdHVzUgZzdGF0dXMSFAoFdGl0bGUYBSABKA'
    'lSBXRpdGxlEiEKDGFtb3VudF9taW5vchgGIAEoA1ILYW1vdW50TWlub3ISGgoIY3VycmVuY3kY'
    'ByABKAlSCGN1cnJlbmN5Eh0KCmFjY291bnRfaWQYCCABKAlSCWFjY291bnRJZBIfCgtjYXRlZ2'
    '9yeV9pZBgJIAEoCVIKY2F0ZWdvcnlJZA==');

@$core.Deprecated('Use listOccurrencesResponseDescriptor instead')
const ListOccurrencesResponse$json = {
  '1': 'ListOccurrencesResponse',
  '2': [
    {
      '1': 'occurrences',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.PlanOccurrence',
      '10': 'occurrences'
    },
  ],
};

/// Descriptor for `ListOccurrencesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listOccurrencesResponseDescriptor =
    $convert.base64Decode(
        'ChdMaXN0T2NjdXJyZW5jZXNSZXNwb25zZRI8CgtvY2N1cnJlbmNlcxgBIAMoCzIaLnBydWRlbn'
        'QudjEuUGxhbk9jY3VycmVuY2VSC29jY3VycmVuY2Vz');
