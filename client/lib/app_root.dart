import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'auth/auth_flow.dart';
import 'home_shell.dart';
import 'splash_screen.dart';

/// Routes on the identity session: anonymous -> the auth flow, a forced password reset -> the
/// set-password screen, authenticated -> the home shell.
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
