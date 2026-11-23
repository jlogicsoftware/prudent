import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a signed-in person adds to Settings: their profile page and a way to sign out.
///
/// A person, a sign-in and a session are the server-connected app's — sign-in is `zen_identity`'s,
/// and this package cannot import it (ADR-108). The app that has one provides a [SettingsSession];
/// an app with no sign-in leaves [settingsSessionProvider] at `null`, and Settings then shows neither
/// the profile entry nor the log-out button.
class SettingsSession {
  const SettingsSession({
    required this.profileBuilder,
    required this.signOut,
    this.setLanguage,
  });

  /// The screen the Profile entry opens.
  final WidgetBuilder profileBuilder;

  /// Ends the session. Also what erasing the account ends with (`PrivacyActions.erase`).
  final Future<void> Function() signOut;

  /// Tells the server the language the person has just chosen, so the e-mail it sends later
  /// (the dormancy warning, ADR-073) is in that language. Throws when the server refuses or cannot
  /// be reached; Settings reports that and leaves the device language as chosen (ADR-130). `null`
  /// for an app with nothing to tell.
  final Future<void> Function(String language)? setLanguage;
}

final settingsSessionProvider = Provider<SettingsSession?>((ref) => null);
