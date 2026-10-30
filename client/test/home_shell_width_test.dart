import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/content_width.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/settings.pb.dart';
import 'package:prudent/home_shell.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/notification/notification_providers.dart';
import 'package:prudent/notification/reminder_notification_outcome.dart';
import 'package:prudent/providers.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class _Accounts extends AccountsNotifier {
  @override
  Future<List<Account>> build() async => [];
}

class _Settings extends SettingsNotifier {
  @override
  Future<Settings> build() async => Settings();
}

void main() {
  for (final width in [400.0, 1600.0]) {
    testWidgets('shell bounds its page body at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsProvider.overrideWith(_Accounts.new),
            settingsProvider.overrideWith(_Settings.new),
            reminderNotificationSyncProvider.overrideWith(
              (ref) async => const ReminderNotificationResult(
                ReminderNotificationOutcome.unsupported,
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: [
              ...PrudentLocalizations.localizationsDelegates,
              zenWidgetsLocaleDelegate,
              navigationLocaleDelegate,
            ],
            supportedLocales: PrudentLocalizations.supportedLocales,
            home: const HomeShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final body = find.byType(ZenContentWidth).first;
      final content =
          find.descendant(of: body, matching: find.byType(Center)).first;
      final available = tester.getSize(body).width;
      final actual = tester.getSize(content).width;
      expect(
        actual,
        closeTo(width == 400 ? available - 32 : prudentContentMaxWidth, 0.1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
