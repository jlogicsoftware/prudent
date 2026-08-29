// This is a generated file - do not edit.
//
// Generated from prudent/v1/settings.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// The settings of the authenticated user.
///
/// NO user_id FIELD, in either direction. Ownership is the JWT `sub`, resolved server-side — and
/// on a singleton it is also the entire addressing scheme: the URL names no id because the token
/// already says whose settings these are.
class Settings extends $pb.GeneratedMessage {
  factory Settings({
    $core.String? mainCurrency,
  }) {
    final result = create();
    if (mainCurrency != null) result.mainCurrency = mainCurrency;
    return result;
  }

  Settings._();

  factory Settings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Settings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Settings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mainCurrency')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Settings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Settings copyWith(void Function(Settings) updates) =>
      super.copyWith((message) => updates(message as Settings)) as Settings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Settings create() => Settings._();
  @$core.override
  Settings createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Settings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Settings>(create);
  static Settings? _defaultInstance;

  /// The user's main currency — ISO-4217, validated server-side.
  ///
  /// A LABEL, NOT A CONVERSION TARGET, and that distinction is the whole decision (ADR-009).
  /// It selects which currency a record form pre-selects, which per-currency total the overview
  /// shows first, and what an empty state names. It is NEVER used to convert one currency into
  /// another or to sum across them.
  ///
  /// Prudent does no FX. A single total across PLN, EUR and USD would need a rate source, a base
  /// currency and a rate DATE stored on every record — a 2024 purchase converted at today's rate
  /// is a wrong number that looks right, which is the class of defect the int64 money type exists
  /// to prevent. Totals stay per-currency and summing across them is refused. If FX is ever added
  /// it is its own ADR and its own fields, not a reinterpretation of this one.
  ///
  /// NOT required to be a currency any of the user's accounts holds. It is a display preference,
  /// and a user who has chosen PLN before opening their first account is a normal state, not an
  /// inconsistency to reject.
  ///
  /// NEVER EMPTY ON A RESPONSE. proto3 has no presence for a string, so "" and "unset" are the same
  /// bytes; rather than leave the client to guess, the server resolves the default before
  /// answering, so a GET always names a real currency. On a request, "" means "reset to the
  /// default" — see UpdateSettingsRequest.
  @$pb.TagNumber(1)
  $core.String get mainCurrency => $_getSZ(0);
  @$pb.TagNumber(1)
  set mainCurrency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMainCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearMainCurrency() => $_clearField(1);
}

/// PUT /api/v1/settings — a FULL REPLACEMENT, for the presence reason set out in categories.proto.
///
/// Responds with the resulting `Settings`, not with an empty body: the server may have substituted
/// a default, and a client that has to re-read to find out what it just wrote is a round trip that
/// the response could have saved.
class UpdateSettingsRequest extends $pb.GeneratedMessage {
  factory UpdateSettingsRequest({
    $core.String? mainCurrency,
  }) {
    final result = create();
    if (mainCurrency != null) result.mainCurrency = mainCurrency;
    return result;
  }

  UpdateSettingsRequest._();

  factory UpdateSettingsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateSettingsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateSettingsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'prudent.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mainCurrency')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateSettingsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateSettingsRequest copyWith(
          void Function(UpdateSettingsRequest) updates) =>
      super.copyWith((message) => updates(message as UpdateSettingsRequest))
          as UpdateSettingsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateSettingsRequest create() => UpdateSettingsRequest._();
  @$core.override
  UpdateSettingsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateSettingsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateSettingsRequest>(create);
  static UpdateSettingsRequest? _defaultInstance;

  /// An EMPTY value means "reset to the default" rather than "leave unchanged" — the full-
  /// replacement rule, applied to the one field. There is no way to say "leave unchanged" because
  /// there is nothing else in the message to leave alone; when a second field lands here, that
  /// sentence stops being true and this comment is the reminder to re-decide rather than inherit.
  @$pb.TagNumber(1)
  $core.String get mainCurrency => $_getSZ(0);
  @$pb.TagNumber(1)
  set mainCurrency($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMainCurrency() => $_has(0);
  @$pb.TagNumber(1)
  void clearMainCurrency() => $_clearField(1);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
