import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'auth/auth_flow.dart';
import 'package:prudent_ui/home_shell.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';
import 'package:prudent_ui/splash_screen.dart';

/// Routes on the identity session: anonymous -> the auth flow, a forced password reset -> the
/// set-password screen, authenticated -> the home shell.
///
/// Once per launch, signed in or not, it removes the copies a file dialog left behind: those of a
/// launch that ended with a dialog open, and of an earlier build (ADR-138).
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  @override
  void initState() {
    super.initState();
    // Nothing waits on it: no dialog can be open before the first screen is, and a failure is logged
    // where it happens and tried again at the next pick or launch.
    unawaited(const PickerCopies().remove());
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(identitySessionStoreProvider);

    return session.when(
      loading: () => const SplashScreen(),
      error: (_, _) => const AuthFlow(),
      data: (identity) {
        if (identity == null) return const AuthFlow();
        if (ref.watch(passwordResetRequiredProvider)) return const SetPasswordScreen();
        return const HomeShell();
      },
    );
  }
}
