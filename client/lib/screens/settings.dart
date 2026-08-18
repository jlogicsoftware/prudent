import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';

import '../account/account_screen.dart';
import '../category/categories_screen.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final t = PrudentLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: Column(
        children: [
          TextButton(
            style: const ButtonStyle(splashFactory: NoSplash.splashFactory),
            onPressed:
                () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AccountScreen())),
            child: Text(t.accountsTitle),
          ),
          TextButton(
            style: const ButtonStyle(splashFactory: NoSplash.splashFactory),
            onPressed:
                () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const CategoriesScreen())),
            child: Text(t.categoriesTitle),
          ),
          ListTile(
            title: Text(t.settingsLanguage),
            // Each language's own name (autonym), not translated per-locale — a language picker
            // conventionally names every option in itself, so a Polish speaker still finds
            // "Українська" rather than a Polish transliteration of it.
            trailing: DropdownButton<String>(
              value: locale.languageCode,
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'uk', child: Text('Українська')),
                DropdownMenuItem(value: 'pl', child: Text('Polski')),
              ],
              onChanged: (code) {
                if (code != null) ref.read(localeProvider.notifier).setLocale(Locale(code));
              },
            ),
          ),
          Text(t.settingsCorrespondents),
          Text(t.settingsProfile),
          Text(t.settingsHelp),
          const Spacer(),
          TextButton(
            onPressed: () => ref.read(identitySessionStoreProvider.notifier).logout(),
            child: Text(t.settingsLogOut),
          ),
        ],
      ),
    );
  }
}
