// This is a generated file - do not edit.
//
// Generated from prudent/v1/privacy.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'accounts.pb.dart' as $1;
import 'budgets.pb.dart' as $5;
import 'categories.pb.dart' as $2;
import 'goal_allocations.pb.dart' as $7;
import 'goals.pb.dart' as $6;
import 'plans.pb.dart' as $4;
import 'records.pb.dart' as $3;
import 'settings.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The person's identity record as Prudent's server holds it — the one personal-data row that is not
/// a financial one. It comes from the framework's `users` table, so its fields are the framework's:
/// the sign-in address, the optional names, and the language.
class ExportProfile extends $pb.GeneratedMessage {
  factory ExportProfile({
    $core.String? email,
    $core.String? displayName,
    $core.String? nickname,
    $core.String? language,
    $fixnum.Int64? createdAtMs,
  }) {
    final result = create();
    if (email != null) result.email = email;
    if (displayName != null) result.displayName = displayName;
    if (nickname != null) result.nickname = nickname;
    if (language != null) result.language = language;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    return result;
  }

  ExportProfile._();

  factory ExportProfile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ExportProfile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExportProfile',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'email')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'nickname')
    ..aOS(4, _omitFieldNames ? '' : 'language')
    ..aInt64(5, _omitFieldNames ? '' : 'createdAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportProfile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExportProfile copyWith(void Function(ExportProfile) updates) =>
      super.copyWith((message) => updates(message as ExportProfile))
          as ExportProfile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ExportProfile create() => ExportProfile._();
  @$core.override
  ExportProfile createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ExportProfile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExportProfile>(create);
  static ExportProfile? _defaultInstance;

  /// The address the person signs in with.
  @$pb.TagNumber(1)
  $core.String get email => $_getSZ(0);
  @$pb.TagNumber(1)
  set email($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmail() => $_clearField(1);

  /// Free-form names, empty when never set.
  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get nickname => $_getSZ(2);
  @$pb.TagNumber(3)
  set nickname($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNickname() => $_has(2);
  @$pb.TagNumber(3)
  void clearNickname() => $_clearField(3);

  /// A language tag the application supports, e.g. "pl". Empty when never chosen.
  @$pb.TagNumber(4)
  $core.String get language => $_getSZ(3);
  @$pb.TagNumber(4)
  set language($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLanguage() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguage() => $_clearField(4);

  /// When the profile was first created, Unix epoch milliseconds.
  @$pb.TagNumber(5)
  $fixnum.Int64 get createdAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCreatedAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearCreatedAtMs() => $_clearField(5);
}

/// EVERYTHING Prudent stores for the authenticated user, as one document.
///
/// READABLE ON PURPOSE: with `X-Zen-Transport: json` (the default) this is canonical proto3 JSON, so
/// a person can open the file in any editor. Money stays an integer count of minor units under its
/// existing field names — `amount_minor`, `balance_minor` — exactly as the rest of the API says it,
/// because a second spelling of a figure in an export is a second figure someone has to reconcile.
///
/// COMPLETE, NOT VIEW-SHAPED. Each list is every row the user owns, whatever its lifecycle state: an
/// archived category, an archived goal, a skipped occurrence and a revoked carry-over reset are all
/// here, because "my data" is not "my data minus what the screens hide". A list is empty rather than
/// absent when the user has none.
///
/// What is NOT here, and why: balances, budgets' calculated plan/actual/remaining, goal progress and
/// envelopes' sums, analytics — all are calculated from these rows on every read (ADR-044, ADR-050,
/// ADR-052), so exporting them would be exporting the same facts twice.
class DataExport extends $pb.GeneratedMessage {
  factory DataExport({
    $core.int? formatVersion,
    $fixnum.Int64? exportedAtMs,
    ExportProfile? profile,
    $0.Settings? settings,
    $core.Iterable<$1.Account>? accounts,
    $core.Iterable<$2.Category>? categories,
    $core.Iterable<$3.Record>? records,
    $core.Iterable<$4.Plan>? plans,
    $core.Iterable<$4.PlanOccurrence>? occurrences,
    $core.Iterable<$5.Budget>? budgets,
    $core.Iterable<$5.BudgetCarryOverReset>? carryOverResets,
    $core.Iterable<$6.Goal>? goals,
    $core.Iterable<$7.GoalAllocation>? goalAllocations,
  }) {
    final result = create();
    if (formatVersion != null) result.formatVersion = formatVersion;
    if (exportedAtMs != null) result.exportedAtMs = exportedAtMs;
    if (profile != null) result.profile = profile;
    if (settings != null) result.settings = settings;
    if (accounts != null) result.accounts.addAll(accounts);
    if (categories != null) result.categories.addAll(categories);
    if (records != null) result.records.addAll(records);
    if (plans != null) result.plans.addAll(plans);
    if (occurrences != null) result.occurrences.addAll(occurrences);
    if (budgets != null) result.budgets.addAll(budgets);
    if (carryOverResets != null) result.carryOverResets.addAll(carryOverResets);
    if (goals != null) result.goals.addAll(goals);
    if (goalAllocations != null) result.goalAllocations.addAll(goalAllocations);
    return result;
  }

  DataExport._();

  factory DataExport.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DataExport.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DataExport',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'formatVersion')
    ..aInt64(2, _omitFieldNames ? '' : 'exportedAtMs')
    ..aOM<ExportProfile>(3, _omitFieldNames ? '' : 'profile',
        subBuilder: ExportProfile.create)
    ..aOM<$0.Settings>(4, _omitFieldNames ? '' : 'settings',
        subBuilder: $0.Settings.create)
    ..pPM<$1.Account>(5, _omitFieldNames ? '' : 'accounts',
        subBuilder: $1.Account.create)
    ..pPM<$2.Category>(6, _omitFieldNames ? '' : 'categories',
        subBuilder: $2.Category.create)
    ..pPM<$3.Record>(7, _omitFieldNames ? '' : 'records',
        subBuilder: $3.Record.create)
    ..pPM<$4.Plan>(8, _omitFieldNames ? '' : 'plans',
        subBuilder: $4.Plan.create)
    ..pPM<$4.PlanOccurrence>(9, _omitFieldNames ? '' : 'occurrences',
        subBuilder: $4.PlanOccurrence.create)
    ..pPM<$5.Budget>(10, _omitFieldNames ? '' : 'budgets',
        subBuilder: $5.Budget.create)
    ..pPM<$5.BudgetCarryOverReset>(11, _omitFieldNames ? '' : 'carryOverResets',
        subBuilder: $5.BudgetCarryOverReset.create)
    ..pPM<$6.Goal>(12, _omitFieldNames ? '' : 'goals',
        subBuilder: $6.Goal.create)
    ..pPM<$7.GoalAllocation>(13, _omitFieldNames ? '' : 'goalAllocations',
        subBuilder: $7.GoalAllocation.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataExport clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DataExport copyWith(void Function(DataExport) updates) =>
      super.copyWith((message) => updates(message as DataExport)) as DataExport;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DataExport create() => DataExport._();
  @$core.override
  DataExport createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DataExport getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DataExport>(create);
  static DataExport? _defaultInstance;

  /// Names the layout of this document, so a person (or a future importer) can tell which one they
  /// hold. Bumped only when a field is removed or changes meaning; adding one does not.
  @$pb.TagNumber(1)
  $core.int get formatVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set formatVersion($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFormatVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFormatVersion() => $_clearField(1);

  /// When the export was produced, Unix epoch milliseconds.
  @$pb.TagNumber(2)
  $fixnum.Int64 get exportedAtMs => $_getI64(1);
  @$pb.TagNumber(2)
  set exportedAtMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExportedAtMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearExportedAtMs() => $_clearField(2);

  @$pb.TagNumber(3)
  ExportProfile get profile => $_getN(2);
  @$pb.TagNumber(3)
  set profile(ExportProfile value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasProfile() => $_has(2);
  @$pb.TagNumber(3)
  void clearProfile() => $_clearField(3);
  @$pb.TagNumber(3)
  ExportProfile ensureProfile() => $_ensure(2);

  @$pb.TagNumber(4)
  $0.Settings get settings => $_getN(3);
  @$pb.TagNumber(4)
  set settings($0.Settings value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSettings() => $_has(3);
  @$pb.TagNumber(4)
  void clearSettings() => $_clearField(4);
  @$pb.TagNumber(4)
  $0.Settings ensureSettings() => $_ensure(3);

  @$pb.TagNumber(5)
  $pb.PbList<$1.Account> get accounts => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$2.Category> get categories => $_getList(5);

  /// Every record — income, expense, transfer legs and corrections alike, each exactly as stored.
  @$pb.TagNumber(7)
  $pb.PbList<$3.Record> get records => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbList<$4.Plan> get plans => $_getList(7);

  /// Every occurrence of every plan, in any state.
  @$pb.TagNumber(9)
  $pb.PbList<$4.PlanOccurrence> get occurrences => $_getList(8);

  @$pb.TagNumber(10)
  $pb.PbList<$5.Budget> get budgets => $_getList(9);

  /// Including revoked ones: the history is never deleted, only marked.
  @$pb.TagNumber(11)
  $pb.PbList<$5.BudgetCarryOverReset> get carryOverResets => $_getList(10);

  @$pb.TagNumber(12)
  $pb.PbList<$6.Goal> get goals => $_getList(11);

  /// The append-only envelope history; a goal's envelope is the sum of these.
  @$pb.TagNumber(13)
  $pb.PbList<$7.GoalAllocation> get goalAllocations => $_getList(12);
}

/// POST /api/v1/privacy/erase.
///
/// IRREVERSIBLE, and refused unless the person says whose data it is. A route that deletes every
/// financial record a person has must not be one stray request away, so the body has to repeat the
/// address the account signs in with.
class EraseAccountRequest extends $pb.GeneratedMessage {
  factory EraseAccountRequest({
    $core.String? confirmEmail,
  }) {
    final result = create();
    if (confirmEmail != null) result.confirmEmail = confirmEmail;
    return result;
  }

  EraseAccountRequest._();

  factory EraseAccountRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EraseAccountRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EraseAccountRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'confirmEmail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EraseAccountRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EraseAccountRequest copyWith(void Function(EraseAccountRequest) updates) =>
      super.copyWith((message) => updates(message as EraseAccountRequest))
          as EraseAccountRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EraseAccountRequest create() => EraseAccountRequest._();
  @$core.override
  EraseAccountRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EraseAccountRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EraseAccountRequest>(create);
  static EraseAccountRequest? _defaultInstance;

  /// The sign-in address of the account being erased, compared case-insensitively. A mismatch is a
  /// 400 and nothing is deleted.
  @$pb.TagNumber(1)
  $core.String get confirmEmail => $_getSZ(0);
  @$pb.TagNumber(1)
  set confirmEmail($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConfirmEmail() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfirmEmail() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
