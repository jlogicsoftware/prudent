import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'auth_deep_links_stub.dart' if (dart.library.io) 'auth_deep_links_native.dart';

/// Delivers auth links the operating system hands this app to the framework's session store.
///
/// Deep-link *registration* is per-platform and per-application — a scheme in a plist and a
/// manifest, and a plugin to read it — so it lives here rather than in the framework. What the
/// framework provides is the other side: `IdentitySessionStore.consumeAuthLink(uri)` takes a
/// plain [Uri] and does not care how it arrived.
///
/// On the web this is a no-op, by conditional import: there the link *is* how the app was
/// opened, and the session store has already consumed it from `Uri.base` before the first frame.
class AuthDeepLinks extends ConsumerStatefulWidget {
  final Widget child;

  const AuthDeepLinks({required this.child, super.key});

  @override
  ConsumerState<AuthDeepLinks> createState() => _AuthDeepLinksState();
}

class _AuthDeepLinksState extends ConsumerState<AuthDeepLinks> {
  Future<void> Function()? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = subscribeToAuthLinks((uri) {
      if (!mounted) return;
      ref.read(identitySessionStoreProvider.notifier).consumeAuthLink(uri);
    });
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
