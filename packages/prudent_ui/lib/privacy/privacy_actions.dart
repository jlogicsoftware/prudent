import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart';
import '../notification/notification_providers.dart';
import '../prudent_repository.dart';
import '../providers.dart';
import '../settings_session.dart';

/// What a person can ask of the server about their own data: a readable copy of all of it, and its
/// erasure (M0, jlogicsoftware/prudent#48, ADR-071). The repository carries the same calls; this is
/// what a screen uses, so the device is left consistent with the server afterwards.
class PrivacyActions {
  PrivacyActions(this._ref);

  final Ref _ref;

  PrudentRepository get _repository => _ref.read(prudentRepositoryProvider);

  /// Everything the server holds for the user, as indented JSON in the same field names the API
  /// uses — text a person can open in any editor. Throws the server's [ZenError] when it refuses.
  Future<String> exportJson() async {
    final result = await _repository.exportData();
    final data = result.fold((export) => export, (error) => throw error);
    return const JsonEncoder.withIndent('  ').convert(data.toProto3Json());
  }

  /// The same export as a file's content: UTF-8 of [exportJson]'s text, and the name to offer for
  /// it, built from the moment the server made the export so the name says which copy it is.
  /// Throws the server's [ZenError] when it refuses.
  Future<ExportFile> exportFile() async {
    final result = await _repository.exportData();
    final data = result.fold((export) => export, (error) => throw error);
    final text = const JsonEncoder.withIndent('  ').convert(data.toProto3Json());
    final made = DateTime.fromMillisecondsSinceEpoch(data.exportedAtMs.toInt(), isUtc: true);
    final day =
        '${made.year.toString().padLeft(4, '0')}-${made.month.toString().padLeft(2, '0')}-'
        '${made.day.toString().padLeft(2, '0')}';
    return ExportFile(name: 'prudent-export-$day.json', bytes: Uint8List.fromList(utf8.encode(text)));
  }

  /// Erases the user's data on the server, then makes this device forget it and signs out.
  ///
  /// [confirmEmail] is what the person typed; the server compares it with the account's address and
  /// refuses (400, nothing deleted) when they differ, so it is sent as typed rather than checked
  /// here against a copy the client would have to keep in step.
  ///
  /// Once the server has answered, three things on the device would otherwise outlive the account.
  /// The provider caches would show the erased data to whoever signs in next in this process, and the
  /// reminder notifications already scheduled would still fire for plans that no longer exist — so
  /// the caches are dropped and the notification pass is reconciled to "nothing wanted", which
  /// cancels every pending one. The sign-out happens whatever the cancel does: the account is gone,
  /// and a failed cancel is reported afterwards, not instead.
  Future<void> erase(String confirmEmail) async {
    final result = await _repository.eraseAccount(
      EraseAccountRequest(confirmEmail: confirmEmail),
    );
    result.fold((_) {}, (error) => throw error);

    invalidateRepositoryReads(_ref.invalidate);
    try {
      await _ref.read(reminderNotificationSchedulerProvider).reconcile(const []);
    } finally {
      await _ref.read(settingsSessionProvider)?.signOut();
    }
  }
}

/// An export ready to be written to a file: its suggested name and its bytes.
class ExportFile {
  const ExportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

final privacyActionsProvider = Provider<PrivacyActions>(PrivacyActions.new);
