// Deleting an account together with all of its transactions (jlogicsoftware/prudent#201). What a
// green screen would hide is the guard: that cancelling or a wrong phrase sends nothing, that the
// accepted delete asks the server to delete the records too, and that a refusal stays on screen
// with nothing removed.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/account/account_tile.dart';
import 'package:prudent/account/delete_account_form.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'zen_fields.dart';

Finder _button(String label) =>
    find.byWidgetPredicate((widget) => widget is ZenButton && widget.label == label);

void main() {
  late List<http.Request> requests;
  late int deleteStatus;
  late String deleteBody;

  final account = Account(
    id: 'a',
    name: 'Bank',
    type: AccountType.ACCOUNT_TYPE_CARD,
    balances: [CurrencyBalance(currency: 'PLN')],
  );

  Future<void> pumpTile(WidgetTester tester) async {
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        requests.add(request);
        const headers = {'X-Zen-Transport': 'json'};
        if (request.method == 'DELETE') {
          return http.Response(deleteBody, deleteStatus, headers: headers);
        }
        return http.Response(
          jsonEncode({
            'accounts': [
              {'id': 'a', 'name': 'Bank'},
            ],
            'records': <Object>[],
          }),
          200,
          headers: headers,
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client))],
        child: MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: Scaffold(body: AccountTile(account)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFinalStep(WidgetTester tester) async {
    tester.widget<ZenListItemActions>(find.byType(ZenListItemActions)).actions.last.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(_button('Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountForm), findsOneWidget);
  }

  List<http.Request> deletes() => requests.where((r) => r.method == 'DELETE').toList();

  setUp(() {
    requests = [];
    deleteStatus = 204;
    deleteBody = '';
  });

  testWidgets('cancelling either step deletes nothing', (tester) async {
    await pumpTile(tester);
    tester.widget<ZenListItemActions>(find.byType(ZenListItemActions)).actions.last.onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(_button('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountForm), findsNothing);

    await openFinalStep(tester);
    await tester.tap(_button('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(DeleteAccountForm), findsNothing);
    expect(deletes(), isEmpty);
  });

  testWidgets('the delete button stays off until the phrase is typed', (tester) async {
    await pumpTile(tester);
    await openFinalStep(tester);

    const action = 'Delete account and transactions';
    // The button and the form's title share the wording; the button is the ZenButton.
    expect(tester.widget<ZenButton>(_button(action)).onPressed, isNull);

    await tester.enterText(textInput('Type DELETE to confirm'), 'DELET');
    await tester.pump();
    expect(tester.widget<ZenButton>(_button(action)).onPressed, isNull);
    expect(deletes(), isEmpty);

    await tester.enterText(textInput('Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    expect(tester.widget<ZenButton>(_button(action)).onPressed, isNotNull);
  });

  testWidgets('the confirmed delete asks the server to delete the records too', (tester) async {
    await pumpTile(tester);
    await openFinalStep(tester);

    await tester.enterText(textInput('Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    await tester.tap(_button('Delete account and transactions'));
    await tester.pumpAndSettle();

    expect(deletes(), hasLength(1));
    expect(deletes().single.url.path, '/api/v1/accounts/a');
    expect(deletes().single.url.queryParameters['deleteRecords'], 'true');
    expect(find.byType(DeleteAccountForm), findsNothing);
  });

  testWidgets('a refusal stays on screen in the server\'s words', (tester) async {
    deleteStatus = 409;
    deleteBody = jsonEncode({'code': 'conflict', 'message': 'This account still has plans.'});
    await pumpTile(tester);
    await openFinalStep(tester);

    await tester.enterText(textInput('Type DELETE to confirm'), 'DELETE');
    await tester.pump();
    await tester.tap(_button('Delete account and transactions'));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountForm), findsOneWidget);
    expect(find.text('This account still has plans.'), findsOneWidget);
  });

  test('without the flag the repository still sends a plain delete', () async {
    final seen = <Uri>[];
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        seen.add(request.url);
        return http.Response('', 204, headers: const {'X-Zen-Transport': 'json'});
      }),
    );
    final repository = PrudentRepository(client: client);
    await repository.deleteAccount('a');
    await repository.deleteAccount('b', deleteRecords: true);

    expect(seen[0].query, isEmpty);
    expect(seen[1].queryParameters, {'deleteRecords': 'true'});
  });
}
