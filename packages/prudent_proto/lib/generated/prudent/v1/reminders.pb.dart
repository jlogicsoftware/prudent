// This is a generated file - do not edit.
//
// Generated from prudent/v1/reminders.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'plans.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// One reminder, addressed by the occurrence it is about: `occurrence.id` is what the read and
/// unread routes take, and what a screen opens to act on the occurrence (confirm, skip).
class DueReminder extends $pb.GeneratedMessage {
  factory DueReminder({
    $0.PlanOccurrence? occurrence,
    $core.String? remindOn,
    $core.int? leadDays,
    $core.bool? read,
  }) {
    final result = create();
    if (occurrence != null) result.occurrence = occurrence;
    if (remindOn != null) result.remindOn = remindOn;
    if (leadDays != null) result.leadDays = leadDays;
    if (read != null) result.read = read;
    return result;
  }

  DueReminder._();

  factory DueReminder.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DueReminder.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DueReminder',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOM<$0.PlanOccurrence>(1, _omitFieldNames ? '' : 'occurrence',
        subBuilder: $0.PlanOccurrence.create)
    ..aOS(2, _omitFieldNames ? '' : 'remindOn')
    ..aI(3, _omitFieldNames ? '' : 'leadDays', fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'read')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DueReminder clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DueReminder copyWith(void Function(DueReminder) updates) =>
      super.copyWith((message) => updates(message as DueReminder))
          as DueReminder;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DueReminder create() => DueReminder._();
  @$core.override
  DueReminder createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DueReminder getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DueReminder>(create);
  static DueReminder? _defaultInstance;

  /// The occurrence this reminds of, with its plan's fields alongside. Its status is PLANNED while
  /// the occurrence is still ahead (it is within its plan's lead time) and OVERDUE once its date has
  /// passed — which is how a screen tells "due" from "overdue" without working it out again. A
  /// completed or skipped occurrence is resolved and has no reminder, so neither status appears.
  @$pb.TagNumber(1)
  $0.PlanOccurrence get occurrence => $_getN(0);
  @$pb.TagNumber(1)
  set occurrence($0.PlanOccurrence value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOccurrence() => $_has(0);
  @$pb.TagNumber(1)
  void clearOccurrence() => $_clearField(1);
  @$pb.TagNumber(1)
  $0.PlanOccurrence ensureOccurrence() => $_ensure(0);

  /// The civil date the reminder fell due: the occurrence's date less the plan's lead time, in the
  /// plan's own calendar days. ISO-8601 YYYY-MM-DD.
  @$pb.TagNumber(2)
  $core.String get remindOn => $_getSZ(1);
  @$pb.TagNumber(2)
  set remindOn($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRemindOn() => $_has(1);
  @$pb.TagNumber(2)
  void clearRemindOn() => $_clearField(2);

  /// The plan's lead time in days as it is now, so a screen can say "due in 3 days" without a second
  /// call for the plan. One of the lead times plans.proto `Reminder.lead_days` lists.
  @$pb.TagNumber(3)
  $core.int get leadDays => $_getIZ(2);
  @$pb.TagNumber(3)
  set leadDays($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLeadDays() => $_has(2);
  @$pb.TagNumber(3)
  void clearLeadDays() => $_clearField(3);

  /// Whether the user has read it. false is "unread". Read state belongs to the occurrence, so it
  /// survives the plan's reminder being switched off and on again.
  @$pb.TagNumber(4)
  $core.bool get read => $_getBF(3);
  @$pb.TagNumber(4)
  set read($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRead() => $_has(3);
  @$pb.TagNumber(4)
  void clearRead() => $_clearField(4);
}

/// GET /api/v1/reminders, and the answer to POST /api/v1/reminders/read-all: every reminder that is
/// due or overdue now, ordered by the occurrence's date ascending, then id, so the order is total and
/// the most overdue come first. Unpaginated in v1 for the reason records.proto gives for
/// ListRecordsResponse.
class ListRemindersResponse extends $pb.GeneratedMessage {
  factory ListRemindersResponse({
    $core.Iterable<DueReminder>? reminders,
  }) {
    final result = create();
    if (reminders != null) result.reminders.addAll(reminders);
    return result;
  }

  ListRemindersResponse._();

  factory ListRemindersResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListRemindersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListRemindersResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..pPM<DueReminder>(1, _omitFieldNames ? '' : 'reminders',
        subBuilder: DueReminder.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRemindersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListRemindersResponse copyWith(
          void Function(ListRemindersResponse) updates) =>
      super.copyWith((message) => updates(message as ListRemindersResponse))
          as ListRemindersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListRemindersResponse create() => ListRemindersResponse._();
  @$core.override
  ListRemindersResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListRemindersResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListRemindersResponse>(create);
  static ListRemindersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DueReminder> get reminders => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
