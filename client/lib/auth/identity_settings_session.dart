import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:prudent_ui/settings_session.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// Gives Settings the signed-in person's profile page and sign-out, from `zen_ui_identity`. Added to
/// the container's overrides by `main.dart`: the shared package cannot import the identity packages,
/// so it asks for a [SettingsSession] and this app answers it (ADR-108).
final Override identitySettingsSession = settingsSessionProvider.overrideWith(
  (ref) => SettingsSession(
    profileBuilder: (_) => const ProfileScreen(),
    signOut: () async {
      await ref.read(identitySessionStoreProvider.notifier).logout();
    },
  ),
);
