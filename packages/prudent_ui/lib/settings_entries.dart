import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'privacy/privacy_screen.dart';

/// One more page Settings opens, which only one app has: Prudent Local's PIN, sync and devices,
/// conflicts and its data copy (ADR-101). The label is the app's own string, so the app words it.
class SettingsEntry {
  const SettingsEntry({required this.label, required this.builder});

  /// The entry's text, in the person's language.
  final String Function(BuildContext context) label;

  /// The page it opens, as the detail of Settings.
  final WidgetBuilder builder;
}

/// The pages an app adds to Settings, after Accounts and Categories. The server-connected app adds
/// none; Prudent Local adds its own.
final settingsEntriesProvider = Provider<List<SettingsEntry>>((ref) => const []);

/// What Settings' "Privacy and data" opens. The server-connected app's page copies the export to
/// the clipboard and erases the account on the server (ADR-071); Prudent Local has neither a
/// server nor, for its data copy, the clipboard (ADR-100 T14), and puts its own page here.
final privacyScreenProvider = Provider<WidgetBuilder>((ref) => (_) => const PrivacyScreen());
