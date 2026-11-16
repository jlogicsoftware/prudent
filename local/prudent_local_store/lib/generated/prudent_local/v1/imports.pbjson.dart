// This is a generated file - do not edit.
//
// Generated from prudent_local/v1/imports.proto.

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

@$core.Deprecated('Use importPhaseDescriptor instead')
const ImportPhase$json = {
  '1': 'ImportPhase',
  '2': [
    {'1': 'IMPORT_PHASE_UNSPECIFIED', '2': 0},
    {'1': 'IMPORT_PHASE_PARSED', '2': 1},
    {'1': 'IMPORT_PHASE_PREVIEWED', '2': 2},
    {'1': 'IMPORT_PHASE_COMMITTED', '2': 3},
    {'1': 'IMPORT_PHASE_DISCARDED', '2': 4},
    {'1': 'IMPORT_PHASE_EXPIRED', '2': 5},
  ],
};

/// Descriptor for `ImportPhase`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List importPhaseDescriptor = $convert.base64Decode(
    'CgtJbXBvcnRQaGFzZRIcChhJTVBPUlRfUEhBU0VfVU5TUEVDSUZJRUQQABIXChNJTVBPUlRfUE'
    'hBU0VfUEFSU0VEEAESGgoWSU1QT1JUX1BIQVNFX1BSRVZJRVdFRBACEhoKFklNUE9SVF9QSEFT'
    'RV9DT01NSVRURUQQAxIaChZJTVBPUlRfUEhBU0VfRElTQ0FSREVEEAQSGAoUSU1QT1JUX1BIQV'
    'NFX0VYUElSRUQQBQ==');

@$core.Deprecated('Use importRowKindDescriptor instead')
const ImportRowKind$json = {
  '1': 'ImportRowKind',
  '2': [
    {'1': 'IMPORT_ROW_KIND_UNSPECIFIED', '2': 0},
    {'1': 'IMPORT_ROW_KIND_ACCEPTED', '2': 1},
    {'1': 'IMPORT_ROW_KIND_DUPLICATE', '2': 2},
    {'1': 'IMPORT_ROW_KIND_REJECTED', '2': 3},
  ],
};

/// Descriptor for `ImportRowKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List importRowKindDescriptor = $convert.base64Decode(
    'Cg1JbXBvcnRSb3dLaW5kEh8KG0lNUE9SVF9ST1dfS0lORF9VTlNQRUNJRklFRBAAEhwKGElNUE'
    '9SVF9ST1dfS0lORF9BQ0NFUFRFRBABEh0KGUlNUE9SVF9ST1dfS0lORF9EVVBMSUNBVEUQAhIc'
    'ChhJTVBPUlRfUk9XX0tJTkRfUkVKRUNURUQQAw==');

@$core.Deprecated('Use localImportRowDescriptor instead')
const LocalImportRow$json = {
  '1': 'LocalImportRow',
  '2': [
    {'1': 'row_number', '3': 1, '4': 1, '5': 5, '10': 'rowNumber'},
    {
      '1': 'kind',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.prudent_local.v1.ImportRowKind',
      '10': 'kind'
    },
    {'1': 'rejection_code', '3': 3, '4': 1, '5': 9, '10': 'rejectionCode'},
    {
      '1': 'transaction_date',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'transactionDate',
      '17': true
    },
    {
      '1': 'booking_date',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'bookingDate',
      '17': true
    },
    {
      '1': 'amount_minor',
      '3': 6,
      '4': 1,
      '5': 3,
      '9': 2,
      '10': 'amountMinor',
      '17': true
    },
    {
      '1': 'description',
      '3': 7,
      '4': 1,
      '5': 12,
      '9': 3,
      '10': 'description',
      '17': true
    },
    {
      '1': 'counterparty',
      '3': 8,
      '4': 1,
      '5': 12,
      '9': 4,
      '10': 'counterparty',
      '17': true
    },
    {
      '1': 'counterparty_account',
      '3': 9,
      '4': 1,
      '5': 12,
      '9': 5,
      '10': 'counterpartyAccount',
      '17': true
    },
    {
      '1': 'external_id',
      '3': 10,
      '4': 1,
      '5': 12,
      '9': 6,
      '10': 'externalId',
      '17': true
    },
    {'1': 'duplicate_code', '3': 11, '4': 1, '5': 9, '10': 'duplicateCode'},
    {
      '1': 'category_id',
      '3': 12,
      '4': 1,
      '5': 9,
      '9': 7,
      '10': 'categoryId',
      '17': true
    },
    {'1': 'note', '3': 13, '4': 1, '5': 9, '9': 8, '10': 'note', '17': true},
    {
      '1': 'include_duplicate',
      '3': 14,
      '4': 1,
      '5': 8,
      '10': 'includeDuplicate'
    },
    {'1': 'hint_code', '3': 15, '4': 1, '5': 9, '10': 'hintCode'},
    {
      '1': 'fingerprint',
      '3': 16,
      '4': 1,
      '5': 9,
      '9': 9,
      '10': 'fingerprint',
      '17': true
    },
    {
      '1': 'occurrence',
      '3': 17,
      '4': 1,
      '5': 5,
      '9': 10,
      '10': 'occurrence',
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
    {'1': '_category_id'},
    {'1': '_note'},
    {'1': '_fingerprint'},
    {'1': '_occurrence'},
  ],
};

/// Descriptor for `LocalImportRow`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localImportRowDescriptor = $convert.base64Decode(
    'Cg5Mb2NhbEltcG9ydFJvdxIdCgpyb3dfbnVtYmVyGAEgASgFUglyb3dOdW1iZXISMwoEa2luZB'
    'gCIAEoDjIfLnBydWRlbnRfbG9jYWwudjEuSW1wb3J0Um93S2luZFIEa2luZBIlCg5yZWplY3Rp'
    'b25fY29kZRgDIAEoCVINcmVqZWN0aW9uQ29kZRIuChB0cmFuc2FjdGlvbl9kYXRlGAQgASgJSA'
    'BSD3RyYW5zYWN0aW9uRGF0ZYgBARImCgxib29raW5nX2RhdGUYBSABKAlIAVILYm9va2luZ0Rh'
    'dGWIAQESJgoMYW1vdW50X21pbm9yGAYgASgDSAJSC2Ftb3VudE1pbm9yiAEBEiUKC2Rlc2NyaX'
    'B0aW9uGAcgASgMSANSC2Rlc2NyaXB0aW9uiAEBEicKDGNvdW50ZXJwYXJ0eRgIIAEoDEgEUgxj'
    'b3VudGVycGFydHmIAQESNgoUY291bnRlcnBhcnR5X2FjY291bnQYCSABKAxIBVITY291bnRlcn'
    'BhcnR5QWNjb3VudIgBARIkCgtleHRlcm5hbF9pZBgKIAEoDEgGUgpleHRlcm5hbElkiAEBEiUK'
    'DmR1cGxpY2F0ZV9jb2RlGAsgASgJUg1kdXBsaWNhdGVDb2RlEiQKC2NhdGVnb3J5X2lkGAwgAS'
    'gJSAdSCmNhdGVnb3J5SWSIAQESFwoEbm90ZRgNIAEoCUgIUgRub3RliAEBEisKEWluY2x1ZGVf'
    'ZHVwbGljYXRlGA4gASgIUhBpbmNsdWRlRHVwbGljYXRlEhsKCWhpbnRfY29kZRgPIAEoCVIIaG'
    'ludENvZGUSJQoLZmluZ2VycHJpbnQYECABKAlICVILZmluZ2VycHJpbnSIAQESIwoKb2NjdXJy'
    'ZW5jZRgRIAEoBUgKUgpvY2N1cnJlbmNliAEBQhMKEV90cmFuc2FjdGlvbl9kYXRlQg8KDV9ib2'
    '9raW5nX2RhdGVCDwoNX2Ftb3VudF9taW5vckIOCgxfZGVzY3JpcHRpb25CDwoNX2NvdW50ZXJw'
    'YXJ0eUIXChVfY291bnRlcnBhcnR5X2FjY291bnRCDgoMX2V4dGVybmFsX2lkQg4KDF9jYXRlZ2'
    '9yeV9pZEIHCgVfbm90ZUIOCgxfZmluZ2VycHJpbnRCDQoLX29jY3VycmVuY2U=');

@$core.Deprecated('Use commitPlanDescriptor instead')
const CommitPlan$json = {
  '1': 'CommitPlan',
  '2': [
    {'1': 'record_ids', '3': 1, '4': 3, '5': 9, '10': 'recordIds'},
    {'1': 'written', '3': 2, '4': 1, '5': 5, '10': 'written'},
    {'1': 'already_imported', '3': 3, '4': 1, '5': 5, '10': 'alreadyImported'},
  ],
};

/// Descriptor for `CommitPlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitPlanDescriptor = $convert.base64Decode(
    'CgpDb21taXRQbGFuEh0KCnJlY29yZF9pZHMYASADKAlSCXJlY29yZElkcxIYCgd3cml0dGVuGA'
    'IgASgFUgd3cml0dGVuEikKEGFscmVhZHlfaW1wb3J0ZWQYAyABKAVSD2FscmVhZHlJbXBvcnRl'
    'ZA==');

@$core.Deprecated('Use localImportSessionDescriptor instead')
const LocalImportSession$json = {
  '1': 'LocalImportSession',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'format_id', '3': 2, '4': 1, '5': 9, '10': 'formatId'},
    {
      '1': 'phase',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.prudent_local.v1.ImportPhase',
      '10': 'phase'
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
      '1': 'phase_changed_at_ms',
      '3': 7,
      '4': 1,
      '5': 3,
      '10': 'phaseChangedAtMs'
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
      '6': '.prudent_local.v1.LocalImportRow',
      '10': 'rows'
    },
    {
      '1': 'committed_written',
      '3': 13,
      '4': 1,
      '5': 5,
      '9': 1,
      '10': 'committedWritten',
      '17': true
    },
    {
      '1': 'committed_already_imported',
      '3': 14,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'committedAlreadyImported',
      '17': true
    },
    {
      '1': 'default_expense_category_id',
      '3': 15,
      '4': 1,
      '5': 9,
      '9': 3,
      '10': 'defaultExpenseCategoryId',
      '17': true
    },
    {
      '1': 'default_income_category_id',
      '3': 16,
      '4': 1,
      '5': 9,
      '9': 4,
      '10': 'defaultIncomeCategoryId',
      '17': true
    },
    {
      '1': 'statement_identity',
      '3': 17,
      '4': 1,
      '5': 9,
      '9': 5,
      '10': 'statementIdentity',
      '17': true
    },
    {
      '1': 'commit_plan',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.CommitPlan',
      '10': 'commitPlan'
    },
  ],
  '8': [
    {'1': '_account_id'},
    {'1': '_committed_written'},
    {'1': '_committed_already_imported'},
    {'1': '_default_expense_category_id'},
    {'1': '_default_income_category_id'},
    {'1': '_statement_identity'},
  ],
};

/// Descriptor for `LocalImportSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List localImportSessionDescriptor = $convert.base64Decode(
    'ChJMb2NhbEltcG9ydFNlc3Npb24SDgoCaWQYASABKAlSAmlkEhsKCWZvcm1hdF9pZBgCIAEoCV'
    'IIZm9ybWF0SWQSMwoFcGhhc2UYAyABKA4yHS5wcnVkZW50X2xvY2FsLnYxLkltcG9ydFBoYXNl'
    'UgVwaGFzZRIiCgphY2NvdW50X2lkGAQgASgJSABSCWFjY291bnRJZIgBARIaCghjdXJyZW5jeR'
    'gFIAEoCVIIY3VycmVuY3kSIgoNY3JlYXRlZF9hdF9tcxgGIAEoA1ILY3JlYXRlZEF0TXMSLQoT'
    'cGhhc2VfY2hhbmdlZF9hdF9tcxgHIAEoA1IQcGhhc2VDaGFuZ2VkQXRNcxIiCg1leHBpcmVzX2'
    'F0X21zGAggASgDUgtleHBpcmVzQXRNcxIjCg1hY2NlcHRlZF9yb3dzGAkgASgFUgxhY2NlcHRl'
    'ZFJvd3MSJQoOZHVwbGljYXRlX3Jvd3MYCiABKAVSDWR1cGxpY2F0ZVJvd3MSIwoNcmVqZWN0ZW'
    'Rfcm93cxgLIAEoBVIMcmVqZWN0ZWRSb3dzEjQKBHJvd3MYDCADKAsyIC5wcnVkZW50X2xvY2Fs'
    'LnYxLkxvY2FsSW1wb3J0Um93UgRyb3dzEjAKEWNvbW1pdHRlZF93cml0dGVuGA0gASgFSAFSEG'
    'NvbW1pdHRlZFdyaXR0ZW6IAQESQQoaY29tbWl0dGVkX2FscmVhZHlfaW1wb3J0ZWQYDiABKAVI'
    'AlIYY29tbWl0dGVkQWxyZWFkeUltcG9ydGVkiAEBEkIKG2RlZmF1bHRfZXhwZW5zZV9jYXRlZ2'
    '9yeV9pZBgPIAEoCUgDUhhkZWZhdWx0RXhwZW5zZUNhdGVnb3J5SWSIAQESQAoaZGVmYXVsdF9p'
    'bmNvbWVfY2F0ZWdvcnlfaWQYECABKAlIBFIXZGVmYXVsdEluY29tZUNhdGVnb3J5SWSIAQESMg'
    'oSc3RhdGVtZW50X2lkZW50aXR5GBEgASgJSAVSEXN0YXRlbWVudElkZW50aXR5iAEBEj0KC2Nv'
    'bW1pdF9wbGFuGBIgASgLMhwucHJ1ZGVudF9sb2NhbC52MS5Db21taXRQbGFuUgpjb21taXRQbG'
    'FuQg0KC19hY2NvdW50X2lkQhQKEl9jb21taXR0ZWRfd3JpdHRlbkIdChtfY29tbWl0dGVkX2Fs'
    'cmVhZHlfaW1wb3J0ZWRCHgocX2RlZmF1bHRfZXhwZW5zZV9jYXRlZ29yeV9pZEIdChtfZGVmYX'
    'VsdF9pbmNvbWVfY2F0ZWdvcnlfaWRCFQoTX3N0YXRlbWVudF9pZGVudGl0eQ==');
