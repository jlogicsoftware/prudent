import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'account/account_screen.dart';
import 'category/categories_screen.dart';
import 'l10n/generated/prudent_localizations.dart';
import 'providers.dart';

/// Each language's own name (autonym), not translated per-locale — a language picker
/// conventionally names every option in itself, so a Polish speaker still finds "Українська"
/// rather than a Polish transliteration of it.
const _languageNames = {'en': 'English', 'uk': 'Українська', 'pl': 'Polski'};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final t = PrudentLocalizations.of(context);

    // Accounts, Categories and Profile open as the detail of this screen (ADR-062): beside it on a
    // wide host, so the navigation sidebar stays, and a full-screen push on a narrow one.
    return ZenDetailHost(
      // The Builder's context sits under the host, which is where showZenDetail looks for it.
      child: Builder(
        builder:
            (context) => ZenPageScaffold(
              title:
                  t.settingsTitle, // Full width, so the actions stay centred: a Column is only as wide as its widest child, and
              // the language select no longer stretches to the edge the way its ListTile did.
              body: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    ZenButton(
                      label: t.accountsTitle,
                      variant: ZenButtonVariant.text,
                      onPressed:
                          () => showZenDetail<void>(
                            context,
                            builder: (_) => const AccountScreen(),
                          ),
                    ),
                    ZenButton(
                      label: t.categoriesTitle,
                      variant: ZenButtonVariant.text,
                      onPressed:
                          () => showZenDetail<void>(
                            context,
                            builder: (_) => const CategoriesScreen(),
                          ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: ZenSelect<String>(
                          label: t.settingsLanguage,
                          items: _languageNames.keys.toList(),
                          itemLabel: (code) => _languageNames[code]!,
                          value: locale.languageCode,
                          onChanged:
                              (code) => ref
                                  .read(localeProvider.notifier)
                                  .setLocale(Locale(code)),
                        ),
                      ),
                    ),
                    ZenButton(
                      label: t.settingsProfile,
                      variant: ZenButtonVariant.text,
                      onPressed:
                          () => showZenDetail<void>(
                            context,
                            builder: (_) => const ProfileScreen(),
                          ),
                    ),
                    const Spacer(),
                    ZenButton(
                      label: t.settingsLogOut,
                      variant: ZenButtonVariant.text,
                      onPressed:
                          () =>
                              ref
                                  .read(identitySessionStoreProvider.notifier)
                                  .logout(),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
