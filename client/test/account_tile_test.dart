import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/account/account_tile.dart';
import 'package:prudent/account/account_edit.dart';
import 'package:prudent/account/reconcile_account.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets(
    'account actions retain edit, reconcile and delete confirmation',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              ...PrudentLocalizations.localizationsDelegates,
              zenWidgetsLocaleDelegate,
            ],
            supportedLocales: PrudentLocalizations.supportedLocales,
            home: Scaffold(
              body: AccountTile(
                Account(
                  id: 'a',
                  name: 'Bank',
                  type: AccountType.ACCOUNT_TYPE_CARD,
                  balances: [CurrencyBalance(currency: 'PLN')],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountEdit), findsOneWidget);
      Navigator.of(tester.element(find.byType(AccountEdit))).pop();
      await tester.pumpAndSettle();

      final actions =
          tester
              .widget<ZenListItemActions>(find.byType(ZenListItemActions))
              .actions;
      actions.first.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(ReconcileAccount), findsOneWidget);
      Navigator.of(tester.element(find.byType(ReconcileAccount))).pop();
      await tester.pumpAndSettle();

      actions.last.onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.text('Delete "Bank"? This cannot be undone.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Bank'), findsOneWidget);
    },
  );
}
