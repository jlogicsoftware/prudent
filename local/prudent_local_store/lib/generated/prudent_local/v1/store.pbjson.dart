// This is a generated file - do not edit.
//
// Generated from prudent_local/v1/store.proto.

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

@$core.Deprecated('Use accountKindDescriptor instead')
const AccountKind$json = {
  '1': 'AccountKind',
  '2': [
    {'1': 'ACCOUNT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'ACCOUNT_KIND_CASH', '2': 1},
    {'1': 'ACCOUNT_KIND_CARD', '2': 2},
    {'1': 'ACCOUNT_KIND_CHECKING', '2': 3},
    {'1': 'ACCOUNT_KIND_SAVINGS', '2': 4},
  ],
};

/// Descriptor for `AccountKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List accountKindDescriptor = $convert.base64Decode(
    'CgtBY2NvdW50S2luZBIcChhBQ0NPVU5UX0tJTkRfVU5TUEVDSUZJRUQQABIVChFBQ0NPVU5UX0'
    'tJTkRfQ0FTSBABEhUKEUFDQ09VTlRfS0lORF9DQVJEEAISGQoVQUNDT1VOVF9LSU5EX0NIRUNL'
    'SU5HEAMSGAoUQUNDT1VOVF9LSU5EX1NBVklOR1MQBA==');

@$core.Deprecated('Use categoryDirectionDescriptor instead')
const CategoryDirection$json = {
  '1': 'CategoryDirection',
  '2': [
    {'1': 'CATEGORY_DIRECTION_UNSPECIFIED', '2': 0},
    {'1': 'CATEGORY_DIRECTION_EXPENSE', '2': 1},
    {'1': 'CATEGORY_DIRECTION_INCOME', '2': 2},
  ],
};

/// Descriptor for `CategoryDirection`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List categoryDirectionDescriptor = $convert.base64Decode(
    'ChFDYXRlZ29yeURpcmVjdGlvbhIiCh5DQVRFR09SWV9ESVJFQ1RJT05fVU5TUEVDSUZJRUQQAB'
    'IeChpDQVRFR09SWV9ESVJFQ1RJT05fRVhQRU5TRRABEh0KGUNBVEVHT1JZX0RJUkVDVElPTl9J'
    'TkNPTUUQAg==');

@$core.Deprecated('Use goalStateDescriptor instead')
const GoalState$json = {
  '1': 'GoalState',
  '2': [
    {'1': 'GOAL_STATE_UNSPECIFIED', '2': 0},
    {'1': 'GOAL_STATE_ACTIVE', '2': 1},
    {'1': 'GOAL_STATE_COMPLETED', '2': 2},
    {'1': 'GOAL_STATE_ARCHIVED', '2': 3},
  ],
};

/// Descriptor for `GoalState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List goalStateDescriptor = $convert.base64Decode(
    'CglHb2FsU3RhdGUSGgoWR09BTF9TVEFURV9VTlNQRUNJRklFRBAAEhUKEUdPQUxfU1RBVEVfQU'
    'NUSVZFEAESGAoUR09BTF9TVEFURV9DT01QTEVURUQQAhIXChNHT0FMX1NUQVRFX0FSQ0hJVkVE'
    'EAM=');

@$core.Deprecated('Use allocationKindDescriptor instead')
const AllocationKind$json = {
  '1': 'AllocationKind',
  '2': [
    {'1': 'ALLOCATION_KIND_UNSPECIFIED', '2': 0},
    {'1': 'ALLOCATION_KIND_ALLOCATE', '2': 1},
    {'1': 'ALLOCATION_KIND_WITHDRAW', '2': 2},
    {'1': 'ALLOCATION_KIND_MOVE', '2': 3},
  ],
};

/// Descriptor for `AllocationKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List allocationKindDescriptor = $convert.base64Decode(
    'Cg5BbGxvY2F0aW9uS2luZBIfChtBTExPQ0FUSU9OX0tJTkRfVU5TUEVDSUZJRUQQABIcChhBTE'
    'xPQ0FUSU9OX0tJTkRfQUxMT0NBVEUQARIcChhBTExPQ0FUSU9OX0tJTkRfV0lUSERSQVcQAhIY'
    'ChRBTExPQ0FUSU9OX0tJTkRfTU9WRRAD');

@$core.Deprecated('Use frequencyDescriptor instead')
const Frequency$json = {
  '1': 'Frequency',
  '2': [
    {'1': 'FREQUENCY_UNSPECIFIED', '2': 0},
    {'1': 'FREQUENCY_ONCE', '2': 1},
    {'1': 'FREQUENCY_DAILY', '2': 2},
    {'1': 'FREQUENCY_WEEKLY', '2': 3},
    {'1': 'FREQUENCY_MONTHLY', '2': 4},
    {'1': 'FREQUENCY_YEARLY', '2': 5},
  ],
};

/// Descriptor for `Frequency`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List frequencyDescriptor = $convert.base64Decode(
    'CglGcmVxdWVuY3kSGQoVRlJFUVVFTkNZX1VOU1BFQ0lGSUVEEAASEgoORlJFUVVFTkNZX09OQ0'
    'UQARITCg9GUkVRVUVOQ1lfREFJTFkQAhIUChBGUkVRVUVOQ1lfV0VFS0xZEAMSFQoRRlJFUVVF'
    'TkNZX01PTlRITFkQBBIUChBGUkVRVUVOQ1lfWUVBUkxZEAU=');

@$core.Deprecated('Use accountDescriptor instead')
const Account$json = {
  '1': 'Account',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'kind',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.prudent_local.v1.AccountKind',
      '10': 'kind'
    },
    {'1': 'active', '3': 4, '4': 1, '5': 8, '10': 'active'},
    {'1': 'include_in_total', '3': 5, '4': 1, '5': 8, '10': 'includeInTotal'},
    {
      '1': 'include_in_overview',
      '3': 6,
      '4': 1,
      '5': 8,
      '10': 'includeInOverview'
    },
    {
      '1': 'eligible_for_goals',
      '3': 7,
      '4': 1,
      '5': 8,
      '10': 'eligibleForGoals'
    },
    {'1': 'account_number', '3': 8, '4': 1, '5': 9, '10': 'accountNumber'},
  ],
};

/// Descriptor for `Account`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountDescriptor = $convert.base64Decode(
    'CgdBY2NvdW50Eg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEjEKBGtpbmQYAy'
    'ABKA4yHS5wcnVkZW50X2xvY2FsLnYxLkFjY291bnRLaW5kUgRraW5kEhYKBmFjdGl2ZRgEIAEo'
    'CFIGYWN0aXZlEigKEGluY2x1ZGVfaW5fdG90YWwYBSABKAhSDmluY2x1ZGVJblRvdGFsEi4KE2'
    'luY2x1ZGVfaW5fb3ZlcnZpZXcYBiABKAhSEWluY2x1ZGVJbk92ZXJ2aWV3EiwKEmVsaWdpYmxl'
    'X2Zvcl9nb2FscxgHIAEoCFIQZWxpZ2libGVGb3JHb2FscxIlCg5hY2NvdW50X251bWJlchgIIA'
    'EoCVINYWNjb3VudE51bWJlcg==');

@$core.Deprecated('Use accountCurrencyDescriptor instead')
const AccountCurrency$json = {
  '1': 'AccountCurrency',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'account_id', '3': 2, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'currency', '3': 3, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'opening_minor', '3': 4, '4': 1, '5': 3, '10': 'openingMinor'},
    {'1': 'position', '3': 5, '4': 1, '5': 5, '10': 'position'},
  ],
};

/// Descriptor for `AccountCurrency`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountCurrencyDescriptor = $convert.base64Decode(
    'Cg9BY2NvdW50Q3VycmVuY3kSDgoCaWQYASABKAlSAmlkEh0KCmFjY291bnRfaWQYAiABKAlSCW'
    'FjY291bnRJZBIaCghjdXJyZW5jeRgDIAEoCVIIY3VycmVuY3kSIwoNb3BlbmluZ19taW5vchgE'
    'IAEoA1IMb3BlbmluZ01pbm9yEhoKCHBvc2l0aW9uGAUgASgFUghwb3NpdGlvbg==');

@$core.Deprecated('Use categoryDescriptor instead')
const Category$json = {
  '1': 'Category',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'icon_key', '3': 3, '4': 1, '5': 9, '10': 'iconKey'},
    {'1': 'description', '3': 4, '4': 1, '5': 9, '10': 'description'},
    {'1': 'color_argb', '3': 5, '4': 1, '5': 13, '10': 'colorArgb'},
    {'1': 'archived', '3': 6, '4': 1, '5': 8, '10': 'archived'},
    {
      '1': 'kind',
      '3': 7,
      '4': 1,
      '5': 14,
      '6': '.prudent_local.v1.CategoryDirection',
      '10': 'kind'
    },
  ],
};

/// Descriptor for `Category`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryDescriptor = $convert.base64Decode(
    'CghDYXRlZ29yeRIOCgJpZBgBIAEoCVICaWQSFAoFdGl0bGUYAiABKAlSBXRpdGxlEhkKCGljb2'
    '5fa2V5GAMgASgJUgdpY29uS2V5EiAKC2Rlc2NyaXB0aW9uGAQgASgJUgtkZXNjcmlwdGlvbhId'
    'Cgpjb2xvcl9hcmdiGAUgASgNUgljb2xvckFyZ2ISGgoIYXJjaGl2ZWQYBiABKAhSCGFyY2hpdm'
    'VkEjcKBGtpbmQYByABKA4yIy5wcnVkZW50X2xvY2FsLnYxLkNhdGVnb3J5RGlyZWN0aW9uUgRr'
    'aW5k');

@$core.Deprecated('Use postingDescriptor instead')
const Posting$json = {
  '1': 'Posting',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'currency', '3': 2, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 3, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `Posting`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List postingDescriptor = $convert.base64Decode(
    'CgdQb3N0aW5nEh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZBIaCghjdXJyZW5jeRgCIA'
    'EoCVIIY3VycmVuY3kSIQoMYW1vdW50X21pbm9yGAMgASgDUgthbW91bnRNaW5vcg==');

@$core.Deprecated('Use correctionIntentDescriptor instead')
const CorrectionIntent$json = {
  '1': 'CorrectionIntent',
  '2': [
    {'1': 'target_minor', '3': 1, '4': 1, '5': 3, '10': 'targetMinor'},
    {'1': 'seen_minor', '3': 2, '4': 1, '5': 3, '10': 'seenMinor'},
    {'1': 'seen_corrections', '3': 3, '4': 3, '5': 9, '10': 'seenCorrections'},
  ],
};

/// Descriptor for `CorrectionIntent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List correctionIntentDescriptor = $convert.base64Decode(
    'ChBDb3JyZWN0aW9uSW50ZW50EiEKDHRhcmdldF9taW5vchgBIAEoA1ILdGFyZ2V0TWlub3ISHQ'
    'oKc2Vlbl9taW5vchgCIAEoA1IJc2Vlbk1pbm9yEikKEHNlZW5fY29ycmVjdGlvbnMYAyADKAlS'
    'D3NlZW5Db3JyZWN0aW9ucw==');

@$core.Deprecated('Use planLinkDescriptor instead')
const PlanLink$json = {
  '1': 'PlanLink',
  '2': [
    {'1': 'plan_id', '3': 1, '4': 1, '5': 9, '10': 'planId'},
    {'1': 'occurrence_id', '3': 2, '4': 1, '5': 9, '10': 'occurrenceId'},
    {'1': 'occurrence_date', '3': 3, '4': 1, '5': 9, '10': 'occurrenceDate'},
  ],
};

/// Descriptor for `PlanLink`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planLinkDescriptor = $convert.base64Decode(
    'CghQbGFuTGluaxIXCgdwbGFuX2lkGAEgASgJUgZwbGFuSWQSIwoNb2NjdXJyZW5jZV9pZBgCIA'
    'EoCVIMb2NjdXJyZW5jZUlkEicKD29jY3VycmVuY2VfZGF0ZRgDIAEoCVIOb2NjdXJyZW5jZURh'
    'dGU=');

@$core.Deprecated('Use importKeyDescriptor instead')
const ImportKey$json = {
  '1': 'ImportKey',
  '2': [
    {'1': 'fingerprint', '3': 1, '4': 1, '5': 9, '10': 'fingerprint'},
    {'1': 'occurrence', '3': 2, '4': 1, '5': 5, '10': 'occurrence'},
  ],
};

/// Descriptor for `ImportKey`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List importKeyDescriptor = $convert.base64Decode(
    'CglJbXBvcnRLZXkSIAoLZmluZ2VycHJpbnQYASABKAlSC2ZpbmdlcnByaW50Eh4KCm9jY3Vycm'
    'VuY2UYAiABKAVSCm9jY3VycmVuY2U=');

@$core.Deprecated('Use recordDescriptor instead')
const Record$json = {
  '1': 'Record',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {
      '1': 'posting',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Posting',
      '10': 'posting'
    },
    {'1': 'date', '3': 4, '4': 1, '5': 9, '10': 'date'},
    {
      '1': 'category_id',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'categoryId',
      '17': true
    },
    {'1': 'payee', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'payee', '17': true},
    {'1': 'note', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'note', '17': true},
    {
      '1': 'correction',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.CorrectionIntent',
      '10': 'correction'
    },
    {
      '1': 'plan_link',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.PlanLink',
      '10': 'planLink'
    },
    {
      '1': 'import_key',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.ImportKey',
      '10': 'importKey'
    },
  ],
  '8': [
    {'1': '_category_id'},
    {'1': '_payee'},
    {'1': '_note'},
  ],
};

/// Descriptor for `Record`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recordDescriptor = $convert.base64Decode(
    'CgZSZWNvcmQSDgoCaWQYASABKAlSAmlkEhQKBXRpdGxlGAIgASgJUgV0aXRsZRIzCgdwb3N0aW'
    '5nGAMgASgLMhkucHJ1ZGVudF9sb2NhbC52MS5Qb3N0aW5nUgdwb3N0aW5nEhIKBGRhdGUYBCAB'
    'KAlSBGRhdGUSJAoLY2F0ZWdvcnlfaWQYBSABKAlIAFIKY2F0ZWdvcnlJZIgBARIZCgVwYXllZR'
    'gGIAEoCUgBUgVwYXllZYgBARIXCgRub3RlGAcgASgJSAJSBG5vdGWIAQESQgoKY29ycmVjdGlv'
    'bhgIIAEoCzIiLnBydWRlbnRfbG9jYWwudjEuQ29ycmVjdGlvbkludGVudFIKY29ycmVjdGlvbh'
    'I3CglwbGFuX2xpbmsYCSABKAsyGi5wcnVkZW50X2xvY2FsLnYxLlBsYW5MaW5rUghwbGFuTGlu'
    'axI6CgppbXBvcnRfa2V5GAogASgLMhsucHJ1ZGVudF9sb2NhbC52MS5JbXBvcnRLZXlSCWltcG'
    '9ydEtleUIOCgxfY2F0ZWdvcnlfaWRCCAoGX3BheWVlQgcKBV9ub3Rl');

@$core.Deprecated('Use transferDescriptor instead')
const Transfer$json = {
  '1': 'Transfer',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'date', '3': 3, '4': 1, '5': 9, '10': 'date'},
    {
      '1': 'source',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Posting',
      '10': 'source'
    },
    {
      '1': 'destination',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Posting',
      '10': 'destination'
    },
  ],
};

/// Descriptor for `Transfer`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transferDescriptor = $convert.base64Decode(
    'CghUcmFuc2ZlchIOCgJpZBgBIAEoCVICaWQSFAoFdGl0bGUYAiABKAlSBXRpdGxlEhIKBGRhdG'
    'UYAyABKAlSBGRhdGUSMQoGc291cmNlGAQgASgLMhkucHJ1ZGVudF9sb2NhbC52MS5Qb3N0aW5n'
    'UgZzb3VyY2USOwoLZGVzdGluYXRpb24YBSABKAsyGS5wcnVkZW50X2xvY2FsLnYxLlBvc3Rpbm'
    'dSC2Rlc3RpbmF0aW9u');

@$core.Deprecated('Use budgetDescriptor instead')
const Budget$json = {
  '1': 'Budget',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'category_id', '3': 2, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'month', '3': 3, '4': 1, '5': 9, '10': 'month'},
    {'1': 'currency', '3': 4, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'amount_minor', '3': 5, '4': 1, '5': 3, '10': 'amountMinor'},
  ],
};

/// Descriptor for `Budget`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List budgetDescriptor = $convert.base64Decode(
    'CgZCdWRnZXQSDgoCaWQYASABKAlSAmlkEh8KC2NhdGVnb3J5X2lkGAIgASgJUgpjYXRlZ29yeU'
    'lkEhQKBW1vbnRoGAMgASgJUgVtb250aBIaCghjdXJyZW5jeRgEIAEoCVIIY3VycmVuY3kSIQoM'
    'YW1vdW50X21pbm9yGAUgASgDUgthbW91bnRNaW5vcg==');

@$core.Deprecated('Use revocationDescriptor instead')
const Revocation$json = {
  '1': 'Revocation',
  '2': [
    {'1': 'by', '3': 1, '4': 1, '5': 9, '10': 'by'},
    {'1': 'at_ms', '3': 2, '4': 1, '5': 3, '10': 'atMs'},
  ],
};

/// Descriptor for `Revocation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List revocationDescriptor = $convert.base64Decode(
    'CgpSZXZvY2F0aW9uEg4KAmJ5GAEgASgJUgJieRITCgVhdF9tcxgCIAEoA1IEYXRNcw==');

@$core.Deprecated('Use budgetCarryOverResetDescriptor instead')
const BudgetCarryOverReset$json = {
  '1': 'BudgetCarryOverReset',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'category_id', '3': 2, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'month', '3': 3, '4': 1, '5': 9, '10': 'month'},
    {'1': 'currency', '3': 4, '4': 1, '5': 9, '10': 'currency'},
    {'1': 'discarded_minor', '3': 5, '4': 1, '5': 3, '10': 'discardedMinor'},
    {'1': 'note', '3': 6, '4': 1, '5': 9, '10': 'note'},
    {'1': 'created_by', '3': 7, '4': 1, '5': 9, '10': 'createdBy'},
    {'1': 'created_at_ms', '3': 8, '4': 1, '5': 3, '10': 'createdAtMs'},
    {
      '1': 'revocation',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Revocation',
      '10': 'revocation'
    },
  ],
};

/// Descriptor for `BudgetCarryOverReset`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List budgetCarryOverResetDescriptor = $convert.base64Decode(
    'ChRCdWRnZXRDYXJyeU92ZXJSZXNldBIOCgJpZBgBIAEoCVICaWQSHwoLY2F0ZWdvcnlfaWQYAi'
    'ABKAlSCmNhdGVnb3J5SWQSFAoFbW9udGgYAyABKAlSBW1vbnRoEhoKCGN1cnJlbmN5GAQgASgJ'
    'UghjdXJyZW5jeRInCg9kaXNjYXJkZWRfbWlub3IYBSABKANSDmRpc2NhcmRlZE1pbm9yEhIKBG'
    '5vdGUYBiABKAlSBG5vdGUSHQoKY3JlYXRlZF9ieRgHIAEoCVIJY3JlYXRlZEJ5EiIKDWNyZWF0'
    'ZWRfYXRfbXMYCCABKANSC2NyZWF0ZWRBdE1zEjwKCnJldm9jYXRpb24YCSABKAsyHC5wcnVkZW'
    '50X2xvY2FsLnYxLlJldm9jYXRpb25SCnJldm9jYXRpb24=');

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
      '6': '.prudent_local.v1.GoalState',
      '10': 'status'
    },
    {
      '1': 'status_changed_at_ms',
      '3': 7,
      '4': 1,
      '5': 3,
      '10': 'statusChangedAtMs'
    },
    {'1': 'created_at_ms', '3': 8, '4': 1, '5': 3, '10': 'createdAtMs'},
  ],
  '8': [
    {'1': '_target_date'},
  ],
};

/// Descriptor for `Goal`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List goalDescriptor = $convert.base64Decode(
    'CgRHb2FsEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEhoKCGN1cnJlbmN5GA'
    'MgASgJUghjdXJyZW5jeRIuChN0YXJnZXRfYW1vdW50X21pbm9yGAQgASgDUhF0YXJnZXRBbW91'
    'bnRNaW5vchIkCgt0YXJnZXRfZGF0ZRgFIAEoCUgAUgp0YXJnZXREYXRliAEBEjMKBnN0YXR1cx'
    'gGIAEoDjIbLnBydWRlbnRfbG9jYWwudjEuR29hbFN0YXRlUgZzdGF0dXMSLwoUc3RhdHVzX2No'
    'YW5nZWRfYXRfbXMYByABKANSEXN0YXR1c0NoYW5nZWRBdE1zEiIKDWNyZWF0ZWRfYXRfbXMYCC'
    'ABKANSC2NyZWF0ZWRBdE1zQg4KDF90YXJnZXRfZGF0ZQ==');

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
      '6': '.prudent_local.v1.AllocationKind',
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
    {'1': 'compensates', '3': 10, '4': 3, '5': 9, '10': 'compensates'},
  ],
  '8': [
    {'1': '_source_goal_id'},
    {'1': '_target_goal_id'},
  ],
};

/// Descriptor for `GoalAllocation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List goalAllocationDescriptor = $convert.base64Decode(
    'Cg5Hb2FsQWxsb2NhdGlvbhIOCgJpZBgBIAEoCVICaWQSNAoEa2luZBgCIAEoDjIgLnBydWRlbn'
    'RfbG9jYWwudjEuQWxsb2NhdGlvbktpbmRSBGtpbmQSKQoOc291cmNlX2dvYWxfaWQYAyABKAlI'
    'AFIMc291cmNlR29hbElkiAEBEikKDnRhcmdldF9nb2FsX2lkGAQgASgJSAFSDHRhcmdldEdvYW'
    'xJZIgBARIaCghjdXJyZW5jeRgFIAEoCVIIY3VycmVuY3kSIQoMYW1vdW50X21pbm9yGAYgASgD'
    'UgthbW91bnRNaW5vchISCgRub3RlGAcgASgJUgRub3RlEiIKDWNyZWF0ZWRfYXRfbXMYCCABKA'
    'NSC2NyZWF0ZWRBdE1zEh0KCmNyZWF0ZWRfYnkYCSABKAlSCWNyZWF0ZWRCeRIgCgtjb21wZW5z'
    'YXRlcxgKIAMoCVILY29tcGVuc2F0ZXNCEQoPX3NvdXJjZV9nb2FsX2lkQhEKD190YXJnZXRfZ2'
    '9hbF9pZA==');

@$core.Deprecated('Use scheduleDescriptor instead')
const Schedule$json = {
  '1': 'Schedule',
  '2': [
    {
      '1': 'frequency',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.prudent_local.v1.Frequency',
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

/// Descriptor for `Schedule`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List scheduleDescriptor = $convert.base64Decode(
    'CghTY2hlZHVsZRI5CglmcmVxdWVuY3kYASABKA4yGy5wcnVkZW50X2xvY2FsLnYxLkZyZXF1ZW'
    '5jeVIJZnJlcXVlbmN5EhoKCGludGVydmFsGAIgASgNUghpbnRlcnZhbBIdCgpzdGFydF9kYXRl'
    'GAMgASgJUglzdGFydERhdGUSGwoJdGltZV96b25lGAQgASgJUgh0aW1lWm9uZRIfCgp1bnRpbF'
    '9kYXRlGAUgASgJSABSCXVudGlsRGF0ZRIrChBvY2N1cnJlbmNlX2NvdW50GAYgASgNSABSD29j'
    'Y3VycmVuY2VDb3VudEIFCgNlbmQ=');

@$core.Deprecated('Use reminderSettingDescriptor instead')
const ReminderSetting$json = {
  '1': 'ReminderSetting',
  '2': [
    {'1': 'enabled', '3': 1, '4': 1, '5': 8, '10': 'enabled'},
    {
      '1': 'lead_days',
      '3': 2,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'leadDays',
      '17': true
    },
  ],
  '8': [
    {'1': '_lead_days'},
  ],
};

/// Descriptor for `ReminderSetting`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reminderSettingDescriptor = $convert.base64Decode(
    'Cg9SZW1pbmRlclNldHRpbmcSGAoHZW5hYmxlZBgBIAEoCFIHZW5hYmxlZBIgCglsZWFkX2RheX'
    'MYAiABKA1IAFIIbGVhZERheXOIAQFCDAoKX2xlYWRfZGF5cw==');

@$core.Deprecated('Use planDescriptor instead')
const Plan$json = {
  '1': 'Plan',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {
      '1': 'posting',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Posting',
      '10': 'posting'
    },
    {'1': 'category_id', '3': 4, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'payee', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'payee', '17': true},
    {'1': 'note', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'note', '17': true},
    {
      '1': 'schedule',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.Schedule',
      '10': 'schedule'
    },
    {
      '1': 'reminder',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.prudent_local.v1.ReminderSetting',
      '10': 'reminder'
    },
  ],
  '8': [
    {'1': '_payee'},
    {'1': '_note'},
  ],
};

/// Descriptor for `Plan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List planDescriptor = $convert.base64Decode(
    'CgRQbGFuEg4KAmlkGAEgASgJUgJpZBIUCgV0aXRsZRgCIAEoCVIFdGl0bGUSMwoHcG9zdGluZx'
    'gDIAEoCzIZLnBydWRlbnRfbG9jYWwudjEuUG9zdGluZ1IHcG9zdGluZxIfCgtjYXRlZ29yeV9p'
    'ZBgEIAEoCVIKY2F0ZWdvcnlJZBIZCgVwYXllZRgFIAEoCUgAUgVwYXllZYgBARIXCgRub3RlGA'
    'YgASgJSAFSBG5vdGWIAQESNgoIc2NoZWR1bGUYByABKAsyGi5wcnVkZW50X2xvY2FsLnYxLlNj'
    'aGVkdWxlUghzY2hlZHVsZRI9CghyZW1pbmRlchgIIAEoCzIhLnBydWRlbnRfbG9jYWwudjEuUm'
    'VtaW5kZXJTZXR0aW5nUghyZW1pbmRlckIICgZfcGF5ZWVCBwoFX25vdGU=');

@$core.Deprecated('Use occurrenceStateDescriptor instead')
const OccurrenceState$json = {
  '1': 'OccurrenceState',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'plan_id', '3': 2, '4': 1, '5': 9, '10': 'planId'},
    {'1': 'occurrence_date', '3': 3, '4': 1, '5': 9, '10': 'occurrenceDate'},
    {'1': 'skipped', '3': 4, '4': 1, '5': 8, '10': 'skipped'},
    {
      '1': 'reminder_read_at_ms',
      '3': 5,
      '4': 1,
      '5': 3,
      '10': 'reminderReadAtMs'
    },
  ],
};

/// Descriptor for `OccurrenceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List occurrenceStateDescriptor = $convert.base64Decode(
    'Cg9PY2N1cnJlbmNlU3RhdGUSDgoCaWQYASABKAlSAmlkEhcKB3BsYW5faWQYAiABKAlSBnBsYW'
    '5JZBInCg9vY2N1cnJlbmNlX2RhdGUYAyABKAlSDm9jY3VycmVuY2VEYXRlEhgKB3NraXBwZWQY'
    'BCABKAhSB3NraXBwZWQSLQoTcmVtaW5kZXJfcmVhZF9hdF9tcxgFIAEoA1IQcmVtaW5kZXJSZW'
    'FkQXRNcw==');

@$core.Deprecated('Use settingsDescriptor instead')
const Settings$json = {
  '1': 'Settings',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'main_currency', '3': 2, '4': 1, '5': 9, '10': 'mainCurrency'},
    {
      '1': 'default_account_id',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'defaultAccountId',
      '17': true
    },
  ],
  '8': [
    {'1': '_default_account_id'},
  ],
};

/// Descriptor for `Settings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List settingsDescriptor = $convert.base64Decode(
    'CghTZXR0aW5ncxIOCgJpZBgBIAEoCVICaWQSIwoNbWFpbl9jdXJyZW5jeRgCIAEoCVIMbWFpbk'
    'N1cnJlbmN5EjEKEmRlZmF1bHRfYWNjb3VudF9pZBgDIAEoCUgAUhBkZWZhdWx0QWNjb3VudElk'
    'iAEBQhUKE19kZWZhdWx0X2FjY291bnRfaWQ=');
