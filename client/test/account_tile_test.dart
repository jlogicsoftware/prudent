import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent_ui/account/account_tile.dart';
import 'package:prudent_ui/account/account_edit.dart';
import 'package:prudent_ui/account/reconcile_account.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
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
              ...GlobalMaterialLocalizations.delegates,
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
        find.text(
          'Delete "Bank"? This also permanently deletes every transaction in this account.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Bank'), findsOneWidget);
    },
  );
}
