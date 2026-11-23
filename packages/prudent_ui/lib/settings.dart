import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'account/account_screen.dart';
import 'category/categories_screen.dart';
import 'l10n/generated/prudent_localizations.dart';
import 'overview/planned_cash_flow.dart';
import 'providers.dart';
import 'settings_entries.dart';
import 'settings_session.dart';

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
    final session = ref.watch(settingsSessionProvider);
    final entries = ref.watch(settingsEntriesProvider);
    final privacyScreen = ref.watch(privacyScreenProvider);

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
              // Scrolls when the entries outgrow the screen (Prudent Local adds three on a phone),
              // and keeps Log Out at the bottom when they do not: the column is at least as tall
              // as the page, and the Spacer takes what is left.
              body: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
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
                    for (final entry in entries)
                      ZenButton(
                        label: entry.label(context),
                        variant: ZenButtonVariant.text,
                        onPressed: () => showZenDetail<void>(context, builder: entry.builder),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ZenSelect<String>(
                        label: t.settingsLanguage,
                        items: _languageNames.keys.toList(),
                        itemLabel: (code) => _languageNames[code]!,
                        value: locale.languageCode,
                        // The switch is immediate; a failed write is not swallowed, it reaches the
                        // error zone, because the choice would not survive a restart.
                        onChanged:
                            (code) => unawaited(
                              ref
                                  .read(localeProvider.notifier)
                                  .setLocale(Locale(code)),
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ZenSwitchRow(
                        label: t.plannedCashFlowToggle,
                        subtitle: t.plannedCashFlowToggleHint(
                          plannedCashFlowDays,
                        ),
                        value: ref.watch(plannedCashFlowVisibleProvider),
                        onChanged:
                            ref
                                .read(plannedCashFlowVisibleProvider.notifier)
                                .set,
                      ),
                    ),
                    if (session != null)
                      ZenButton(
                        label: t.settingsProfile,
                        variant: ZenButtonVariant.text,
                        onPressed:
                            () => showZenDetail<void>(
                              context,
                              builder: session.profileBuilder,
                            ),
                      ),
                    ZenButton(
                      label: t.settingsPrivacy,
                      variant: ZenButtonVariant.text,
                      onPressed:
                          () => showZenDetail<void>(
                            context,
                            builder: privacyScreen,
                          ),
                    ),
                    const Spacer(),
                    if (session != null)
                      ZenButton(
                        label: t.settingsLogOut,
                        variant: ZenButtonVariant.text,
                        onPressed: session.signOut,
                      ),
                  ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
