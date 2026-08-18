import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_secure_store/zen_secure_store.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import 'src/app.dart';
import 'src/auth_deep_links.dart';
import 'src/prudent_repository.dart';
import 'src/providers.dart';

/// Wires Prudent to the real backend. One session [http.Client] ([createSessionClient], the
/// compile-time platform seam: a native cookie jar or a credentialed browser client) is shared by
/// the identity repository and the app repository, so the session cookie set at login is resent
/// on every later call.
///
/// The base URL is the compile-time [zenApiUrl] (`ZEN_API_URL`); the old hardcoded Realtime
/// Database URL is gone (docs/DECISIONS.md ADR-004) — config stays compile-time.
///
/// The session survives the app being closed on the platforms where that does not happen by
/// itself. A browser persists its own cookies; a native process loses everything, so
/// [SecureTokenStore] keeps the refresh token in the platform keystore and
/// [IdentitySessionStore] spends it on the next start.
void main() async {
  // Plugins are reached over platform channels, and the keystore is a plugin, so the binding has
  // to exist before the store is constructed.
  WidgetsFlutterBinding.ensureInitialized();

  // `intl`'s DateFormat throws LocaleDataException for any locale it has not loaded symbol data
  // for — 'en' works without this, {uk, pl} do not. Initializing with no argument loads every
  // locale intl ships, which is what makes `DateFormat.yMd(locale.toLanguageTag())` in
  // new_record.dart safe to call for any of prudentSupportedLocales.
  await initializeDateFormatting();

  // `zenIsWeb` is a const, so this whole branch folds away at compile time: a web build carries
  // no keystore code, and a native build carries no dead check. Null on web is not a gap — the
  // browser already persists the session cookies itself, and the web session client ignores the
  // store for exactly that reason.
  final TokenStore? tokens = zenIsWeb ? null : SecureTokenStore();
  final ZenSessionClient session = createSessionClient(store: tokens);

  // The container is built below, but ZenClient only calls this closure when it sends a request —
  // by which time it is assigned. Reading the notifier per request (rather than capturing a
  // value) is what makes a mid-session language switch take effect immediately, including on
  // `POST /auth/register`, where the server seeds `users.language`.
  late final ProviderContainer container;

  // The 401 -> renew -> replay loop, wired once and shared by every repository. The access token
  // lives an hour; the refresh token behind it lives seven days — without this, a session left
  // open past the hour would fail every call until the app was restarted.
  late final SupabaseIdentityRepository identityRepository;
  Future<bool> recoverSession() async => (await identityRepository.refreshSession()).isSuccess;

  identityRepository = SupabaseIdentityRepository(
    client: ZenClient(
      baseUrl: zenApiUrl,
      httpClient: session,
      language: () => container.read(localeProvider).languageCode,
      recoverSession: recoverSession,
    ),
  );
  final prudentRepository = PrudentRepository(
    client: ZenClient(
      baseUrl: zenApiUrl,
      httpClient: session,
      language: () => container.read(localeProvider).languageCode,
      recoverSession: recoverSession,
    ),
  );

  container = ProviderContainer(
    overrides: [
      identityRepositoryProvider.overrideWithValue(identityRepository),
      prudentRepositoryProvider.overrideWithValue(prudentRepository),
      // The SAME client the repositories use, not another one: the store restores the refresh
      // cookie into this jar, and a second client would restore it into a jar nobody sends from.
      sessionClientProvider.overrideWithValue(session),
    ],
  );

  // AuthDeepLinks wraps the app rather than sitting inside it: it must outlive every screen, since
  // a confirmation link can arrive at any moment. It is inert on the web (conditional import),
  // where links arrive as navigations and the session store has already read them.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AuthDeepLinks(child: PrudentApp()),
    ),
  );
}
