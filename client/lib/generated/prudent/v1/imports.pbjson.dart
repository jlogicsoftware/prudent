// This is a generated file - do not edit.
//
// Generated from prudent/v1/imports.proto.

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

@$core.Deprecated('Use importSessionStateDescriptor instead')
const ImportSessionState$json = {
  '1': 'ImportSessionState',
  '2': [
    {'1': 'IMPORT_SESSION_STATE_UNSPECIFIED', '2': 0},
    {'1': 'IMPORT_SESSION_STATE_PARSED', '2': 1},
    {'1': 'IMPORT_SESSION_STATE_PREVIEWED', '2': 2},
    {'1': 'IMPORT_SESSION_STATE_COMMITTED', '2': 3},
    {'1': 'IMPORT_SESSION_STATE_DISCARDED', '2': 4},
    {'1': 'IMPORT_SESSION_STATE_EXPIRED', '2': 5},
  ],
};

/// Descriptor for `ImportSessionState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List importSessionStateDescriptor = $convert.base64Decode(
    'ChJJbXBvcnRTZXNzaW9uU3RhdGUSJAogSU1QT1JUX1NFU1NJT05fU1RBVEVfVU5TUEVDSUZJRU'
    'QQABIfChtJTVBPUlRfU0VTU0lPTl9TVEFURV9QQVJTRUQQARIiCh5JTVBPUlRfU0VTU0lPTl9T'
    'VEFURV9QUkVWSUVXRUQQAhIiCh5JTVBPUlRfU0VTU0lPTl9TVEFURV9DT01NSVRURUQQAxIiCh'
    '5JTVBPUlRfU0VTU0lPTl9TVEFURV9ESVNDQVJERUQQBBIgChxJTVBPUlRfU0VTU0lPTl9TVEFU'
    'RV9FWFBJUkVEEAU=');

@$core.Deprecated('Use importRowStatusDescriptor instead')
const ImportRowStatus$json = {
  '1': 'ImportRowStatus',
  '2': [
    {'1': 'IMPORT_ROW_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'IMPORT_ROW_STATUS_ACCEPTED', '2': 1},
    {'1': 'IMPORT_ROW_STATUS_DUPLICATE', '2': 2},
    {'1': 'IMPORT_ROW_STATUS_REJECTED', '2': 3},
  ],
};

/// Descriptor for `ImportRowStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List importRowStatusDescriptor = $convert.base64Decode(
    'Cg9JbXBvcnRSb3dTdGF0dXMSIQodSU1QT1JUX1JPV19TVEFUVVNfVU5TUEVDSUZJRUQQABIeCh'
    'pJTVBPUlRfUk9XX1NUQVRVU19BQ0NFUFRFRBABEh8KG0lNUE9SVF9ST1dfU1RBVFVTX0RVUExJ'
    'Q0FURRACEh4KGklNUE9SVF9ST1dfU1RBVFVTX1JFSkVDVEVEEAM=');

@$core.Deprecated('Use importRowDescriptor instead')
const ImportRow$json = {
  '1': 'ImportRow',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'row_number', '3': 2, '4': 1, '5': 5, '10': 'rowNumber'},
    {
      '1': 'status',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.ImportRowStatus',
      '10': 'status'
    },
    {'1': 'rejection_code', '3': 4, '4': 1, '5': 9, '10': 'rejectionCode'},
    {
      '1': 'transaction_date',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'transactionDate',
      '17': true
    },
    {
      '1': 'booking_date',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'bookingDate',
      '17': true
    },
    {
      '1': 'amount_minor',
      '3': 7,
      '4': 1,
      '5': 3,
      '9': 2,
      '10': 'amountMinor',
      '17': true
    },
    {
      '1': 'description',
      '3': 8,
      '4': 1,
      '5': 9,
      '9': 3,
      '10': 'description',
      '17': true
    },
    {
      '1': 'counterparty',
      '3': 9,
      '4': 1,
      '5': 9,
      '9': 4,
      '10': 'counterparty',
      '17': true
    },
    {
      '1': 'counterparty_account',
      '3': 10,
      '4': 1,
      '5': 9,
      '9': 5,
      '10': 'counterpartyAccount',
      '17': true
    },
    {
      '1': 'external_id',
      '3': 11,
      '4': 1,
      '5': 9,
      '9': 6,
      '10': 'externalId',
      '17': true
    },
  ],
  '8': [
    {'1': '_transaction_date'},
    {'1': '_booking_date'},
    {'1': '_amount_minor'},
    {'1': '_description'},
    {'1': '_counterparty'},
    {'1': '_counterparty_account'},
    {'1': '_external_id'},
  ],
};

/// Descriptor for `ImportRow`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importRowDescriptor = $convert.base64Decode(
    'CglJbXBvcnRSb3cSHQoKc2Vzc2lvbl9pZBgBIAEoCVIJc2Vzc2lvbklkEh0KCnJvd19udW1iZX'
    'IYAiABKAVSCXJvd051bWJlchIzCgZzdGF0dXMYAyABKA4yGy5wcnVkZW50LnYxLkltcG9ydFJv'
    'd1N0YXR1c1IGc3RhdHVzEiUKDnJlamVjdGlvbl9jb2RlGAQgASgJUg1yZWplY3Rpb25Db2RlEi'
    '4KEHRyYW5zYWN0aW9uX2RhdGUYBSABKAlIAFIPdHJhbnNhY3Rpb25EYXRliAEBEiYKDGJvb2tp'
    'bmdfZGF0ZRgGIAEoCUgBUgtib29raW5nRGF0ZYgBARImCgxhbW91bnRfbWlub3IYByABKANIAl'
    'ILYW1vdW50TWlub3KIAQESJQoLZGVzY3JpcHRpb24YCCABKAlIA1ILZGVzY3JpcHRpb26IAQES'
    'JwoMY291bnRlcnBhcnR5GAkgASgJSARSDGNvdW50ZXJwYXJ0eYgBARI2ChRjb3VudGVycGFydH'
    'lfYWNjb3VudBgKIAEoCUgFUhNjb3VudGVycGFydHlBY2NvdW50iAEBEiQKC2V4dGVybmFsX2lk'
    'GAsgASgJSAZSCmV4dGVybmFsSWSIAQFCEwoRX3RyYW5zYWN0aW9uX2RhdGVCDwoNX2Jvb2tpbm'
    'dfZGF0ZUIPCg1fYW1vdW50X21pbm9yQg4KDF9kZXNjcmlwdGlvbkIPCg1fY291bnRlcnBhcnR5'
    'QhcKFV9jb3VudGVycGFydHlfYWNjb3VudEIOCgxfZXh0ZXJuYWxfaWQ=');

@$core.Deprecated('Use importSessionDescriptor instead')
const ImportSession$json = {
  '1': 'ImportSession',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'format_id', '3': 2, '4': 1, '5': 9, '10': 'formatId'},
    {
      '1': 'state',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.prudent.v1.ImportSessionState',
      '10': 'state'
    },
    {
      '1': 'account_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'accountId',
      '17': true
    },
    {'1': 'currency', '3': 5, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'created_at_ms', '3': 6, '4': 1, '5': 3, '10': 'createdAtMs'},
    {
      '1': 'state_changed_at_ms',
      '3': 7,
      '4': 1,
      '5': 3,
      '10': 'stateChangedAtMs'
    },
    {'1': 'expires_at_ms', '3': 8, '4': 1, '5': 3, '10': 'expiresAtMs'},
    {'1': 'accepted_rows', '3': 9, '4': 1, '5': 5, '10': 'acceptedRows'},
    {'1': 'duplicate_rows', '3': 10, '4': 1, '5': 5, '10': 'duplicateRows'},
    {'1': 'rejected_rows', '3': 11, '4': 1, '5': 5, '10': 'rejectedRows'},
    {
      '1': 'rows',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.ImportRow',
      '10': 'rows'
    },
  ],
  '8': [
    {'1': '_account_id'},
  ],
};

/// Descriptor for `ImportSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importSessionDescriptor = $convert.base64Decode(
    'Cg1JbXBvcnRTZXNzaW9uEg4KAmlkGAEgASgJUgJpZBIbCglmb3JtYXRfaWQYAiABKAlSCGZvcm'
    '1hdElkEjQKBXN0YXRlGAMgASgOMh4ucHJ1ZGVudC52MS5JbXBvcnRTZXNzaW9uU3RhdGVSBXN0'
    'YXRlEiIKCmFjY291bnRfaWQYBCABKAlIAFIJYWNjb3VudElkiAEBEhoKCGN1cnJlbmN5GAUgAS'
    'gJUghjdXJyZW5jeRIiCg1jcmVhdGVkX2F0X21zGAYgASgDUgtjcmVhdGVkQXRNcxItChNzdGF0'
    'ZV9jaGFuZ2VkX2F0X21zGAcgASgDUhBzdGF0ZUNoYW5nZWRBdE1zEiIKDWV4cGlyZXNfYXRfbX'
    'MYCCABKANSC2V4cGlyZXNBdE1zEiMKDWFjY2VwdGVkX3Jvd3MYCSABKAVSDGFjY2VwdGVkUm93'
    'cxIlCg5kdXBsaWNhdGVfcm93cxgKIAEoBVINZHVwbGljYXRlUm93cxIjCg1yZWplY3RlZF9yb3'
    'dzGAsgASgFUgxyZWplY3RlZFJvd3MSKQoEcm93cxgMIAMoCzIVLnBydWRlbnQudjEuSW1wb3J0'
    'Um93UgRyb3dzQg0KC19hY2NvdW50X2lk');

@$core.Deprecated('Use createImportSessionRequestDescriptor instead')
const CreateImportSessionRequest$json = {
  '1': 'CreateImportSessionRequest',
  '2': [
    {'1': 'format_id', '3': 1, '4': 1, '5': 9, '10': 'formatId'},
    {'1': 'content', '3': 2, '4': 1, '5': 12, '10': 'content'},
    {
      '1': 'account_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'accountId',
      '17': true
    },
  ],
  '8': [
    {'1': '_account_id'},
  ],
};

/// Descriptor for `CreateImportSessionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createImportSessionRequestDescriptor =
    $convert.base64Decode(
        'ChpDcmVhdGVJbXBvcnRTZXNzaW9uUmVxdWVzdBIbCglmb3JtYXRfaWQYASABKAlSCGZvcm1hdE'
        'lkEhgKB2NvbnRlbnQYAiABKAxSB2NvbnRlbnQSIgoKYWNjb3VudF9pZBgDIAEoCUgAUglhY2Nv'
        'dW50SWSIAQFCDQoLX2FjY291bnRfaWQ=');

@$core.Deprecated('Use previewImportSessionRequestDescriptor instead')
const PreviewImportSessionRequest$json = {
  '1': 'PreviewImportSessionRequest',
  '2': [
    {
      '1': 'account_id',
      '3': 1,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'accountId',
      '17': true
    },
  ],
  '8': [
    {'1': '_account_id'},
  ],
};

/// Descriptor for `PreviewImportSessionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List previewImportSessionRequestDescriptor =
    $convert.base64Decode(
        'ChtQcmV2aWV3SW1wb3J0U2Vzc2lvblJlcXVlc3QSIgoKYWNjb3VudF9pZBgBIAEoCUgAUglhY2'
        'NvdW50SWSIAQFCDQoLX2FjY291bnRfaWQ=');

@$core.Deprecated('Use commitImportSessionRequestDescriptor instead')
const CommitImportSessionRequest$json = {
  '1': 'CommitImportSessionRequest',
  '2': [
    {
      '1': 'confirmed_accepted_rows',
      '3': 1,
      '4': 1,
      '5': 5,
      '10': 'confirmedAcceptedRows'
    },
  ],
};

/// Descriptor for `CommitImportSessionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitImportSessionRequestDescriptor =
    $convert.base64Decode(
        'ChpDb21taXRJbXBvcnRTZXNzaW9uUmVxdWVzdBI2Chdjb25maXJtZWRfYWNjZXB0ZWRfcm93cx'
        'gBIAEoBVIVY29uZmlybWVkQWNjZXB0ZWRSb3dz');

@$core.Deprecated('Use listImportSessionsResponseDescriptor instead')
const ListImportSessionsResponse$json = {
  '1': 'ListImportSessionsResponse',
  '2': [
    {
      '1': 'sessions',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.prudent.v1.ImportSession',
      '10': 'sessions'
    },
  ],
};

/// Descriptor for `ListImportSessionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listImportSessionsResponseDescriptor =
    $convert.base64Decode(
        'ChpMaXN0SW1wb3J0U2Vzc2lvbnNSZXNwb25zZRI1CghzZXNzaW9ucxgBIAMoCzIZLnBydWRlbn'
        'QudjEuSW1wb3J0U2Vzc2lvblIIc2Vzc2lvbnM=');
