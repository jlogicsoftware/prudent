// The statement import flow (M6, jlogicsoftware/prudent#74): choose an account and a file, see the
// accepted, duplicate and rejected rows, decide categories, notes and duplicates, confirm. Driven
// through the real PrudentRepository over a mock HTTP server (import_server.dart), so what is asserted
// is the request the screens send and what they show for the answer. All data is synthetic.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:prudent/account/account_screen.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/imports/import_preview_screen.dart';
import 'package:prudent/imports/import_statement_screen.dart';
import 'package:prudent/imports/statement_picker.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import 'import_server.dart';
import 'zen_platform_skip.dart';

class _FixedAccounts extends AccountsNotifier {
  _FixedAccounts(this._accounts);
  final List<Account> _accounts;

  @override
  Future<List<Account>> build() async => _accounts;
}

Account _account(String id, String name, {String number = 'PL00000000000000000000000001', bool active = true}) =>
    Account(
      id: id,
      name: name,
      type: AccountType.ACCOUNT_TYPE_CARD,
      isActive: active,
      accountNumber: number,
      balances: [CurrencyBalance(currency: 'PLN', amountMinor: Int64(0))],
    );

/// Three rows to import (one an own-account transfer), one duplicate, one rejected for a known rule
/// and one for a rule this client has never heard of.
List<Map<String, Object?>> _rows() => [
  importRow(1, amount: -1250, description: 'TEST CARD PAYMENT EXAMPLE', date: '2026-11-03'),
  importRow(
    2,
    amount: 10000,
    description: 'TEST OWN TRANSFER PRÓB',
    date: '2026-11-02',
    hintCode: 'transfer.own_account',
  ),
  importRow(3, amount: -500, description: 'TEST BLIK PURCHASE EXAMPLE'),
  importRow(
    4,
    status: duplicate,
    amount: -2000,
    description: 'TEST DUPLICATE PAYMENT',
    duplicateCode: 'duplicate.already_imported',
  ),
  importRow(5, status: rejected, date: null, rejectionCode: 'description.unknown_shape'),
  importRow(6, status: rejected, date: null, rejectionCode: 'zzz.brand_new'),
];

void _noop() {}

PickedStatement _file() => PickedStatement(
  name: 'statement-example.csv',
  bytes: Uint8List.fromList(utf8.encode('synthetic bytes')),
);

/// A list with one button that opens the import the way Accounts does: through `showZenDetail`, so a
/// wide host puts it in a pane and a narrow one pushes it.
class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const Text('List of accounts'),
        ZenButton(
          label: 'Open import',
          onPressed: () => showZenDetail<void>(context, builder: (_) => const ImportStatementScreen()),
        ),
      ],
    ),
  );
}

Finder _select(String label) =>
    find.byWidgetPredicate((w) => w is ZenSelect<String> && w.label == label);

void _choose(WidgetTester tester, String label, String id) {
  tester.widget<ZenSelect<String>>(_select(label)).onChanged!(id);
}

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ZenButton && w.label == label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ZenButton>(_button(label)).onPressed != null;

void main() {
  late ImportServer server;

  Future<void> pump(
    WidgetTester tester,
    ImportServer s, {
    Widget home = const ImportPreviewScreen(sessionId: 's1', onBackToImport: _noop),
    List<Account>? accounts,
    StatementPicker? picker,
    double width = 800,
  }) async {
    server = s;
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient(s.handle),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
          accountsProvider.overrideWith(
            () => _FixedAccounts(accounts ?? [_account('acc', 'Erste')]),
          ),
          if (picker != null) statementPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ImportServer previewed({String? account = 'acc'}) =>
      ImportServer(rows: _rows(), accountId: account);

  group('review', () {
    testWidgets('previews a fresh session and shows the three groups with their counts', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      // A session fresh from the upload is classified once when the review opens.
      expect(server.count('POST /api/v1/import-sessions/s1/preview'), 1);
      expect(find.text('To import (3)'), findsOneWidget);
      expect(find.text('Duplicates (1)'), findsOneWidget);
      expect(find.text('Not readable (2)'), findsOneWidget);
      expect(find.text('Into Erste in PLN'), findsOneWidget);

      // Accepted rows, with amounts drawn in minor units, never as a double.
      expect(find.text('TEST CARD PAYMENT EXAMPLE'), findsOneWidget);
      expect(find.text('-12.50 PLN'), findsOneWidget);
      expect(find.text('100.00 PLN'), findsOneWidget);
      expect(find.text('TEST DUPLICATE PAYMENT'), findsNothing);
      // The statement's civil date in the app's format, not the wire's ISO text.
      expect(find.text('11/3/2026'), findsOneWidget);
      expect(find.text('2026-11-03'), findsNothing);
    });

    testWidgets('an own-account transfer carries a visible warning not to record a Transfer', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      expect(find.text('Check before importing'), findsOneWidget);
      expect(find.textContaining('never as a Transfer'), findsOneWidget);
    });

    testWidgets('duplicates are listed apart with an explicit import-anyway switch and its risk', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.text('Duplicates (1)'));
      await tester.pumpAndSettle();

      expect(find.text('TEST DUPLICATE PAYMENT'), findsOneWidget);
      expect(find.textContaining('Already imported'), findsOneWidget);
      expect(find.text('Import anyway'), findsOneWidget);
      expect(find.textContaining('it will be counted twice'), findsOneWidget);
      expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow)).value, isFalse);
    });

    testWidgets('including a duplicate sends the decision and moves the confirmed count', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());
      expect(find.text('Import 3 rows'), findsOneWidget);

      await tester.tap(find.text('Duplicates (1)'));
      await tester.pumpAndSettle();
      tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow)).onChanged!(true);
      await tester.pumpAndSettle();

      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/rows/4').single, {
        'includeDuplicate': true,
      });
      // The server's recomputed counts decide what the button confirms.
      expect(find.text('Import 4 rows'), findsOneWidget);
      expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow)).value, isTrue);
    });

    testWidgets('rejected rows are explained by their rule and cannot be edited', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.text('Not readable (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Row 5: not imported'), findsOneWidget);
      expect(find.textContaining('This kind of operation is not supported yet'), findsOneWidget);
      // An unknown code is named, never replaced by the server's text.
      expect(find.textContaining('code zzz.brand_new'), findsOneWidget);
      expect(find.byType(ZenSwitchRow), findsNothing);

      await tester.tap(find.text('Row 5: not imported'));
      await tester.pumpAndSettle();
      expect(find.text('Save row'), findsNothing);
      expect(server.calls.where((c) => c.contains('/rows/')), isEmpty);
    });

    testWidgets('confirm stays disabled until every row has a category or a default applies', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      expect(_enabled(tester, 'Import 3 rows'), isFalse);
      expect(find.textContaining('3 rows need a category'), findsOneWidget);

      _choose(tester, 'Default category for expenses', 'food');
      await tester.pumpAndSettle();
      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/defaults').single, {
        'defaultExpenseCategoryId': 'food',
      });
      // The income row still has none.
      expect(_enabled(tester, 'Import 3 rows'), isFalse);
      expect(find.textContaining('1 row needs a category'), findsOneWidget);

      _choose(tester, 'Default category for income', 'salary');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'Import 3 rows'), isTrue);
    });

    testWidgets('a row editor offers only categories that suit the row and sends what changed', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.text('TEST CARD PAYMENT EXAMPLE'));
      await tester.pumpAndSettle();

      expect(find.text('Row 1'), findsOneWidget);
      final select = tester.widget<ZenSelect<String>>(_select('Category'));
      // An expense row: expense and unspecified categories, not income, not archived.
      expect(select.items, ['', 'food', 'misc']);

      select.onChanged!('food');
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'weekly shop');
      await tester.tap(find.text('Save row'));
      await tester.pumpAndSettle();

      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/rows/1').single, {
        'categoryId': 'food',
        'note': 'weekly shop',
      });
      expect(find.text('Category: Food'), findsOneWidget);
      expect(find.text('Note: weekly shop'), findsOneWidget);
    });

    testWidgets('an income row is offered income categories only', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.text('TEST OWN TRANSFER PRÓB'));
      await tester.pumpAndSettle();

      expect(tester.widget<ZenSelect<String>>(_select('Category')).items, ['', 'salary', 'misc']);
    });

    testWidgets('confirming sends exactly the accepted count the server returned and shows the result', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      _choose(tester, 'Default category for expenses', 'food');
      await tester.pumpAndSettle();
      _choose(tester, 'Default category for income', 'salary');
      await tester.pumpAndSettle();
      await tester.tap(_button('Import 3 rows'));
      await tester.pumpAndSettle();

      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/commit').single, {
        'confirmedAcceptedRows': 3,
      });
      expect(find.text('Import finished'), findsWidgets);
      expect(find.text('3 records were added.'), findsOneWidget);
      expect(find.text('Back to accounts'), findsOneWidget);
    });

    testWidgets('the result also names rows that were already in the account', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed()
        ..state = 'IMPORT_SESSION_STATE_COMMITTED'
        ..committedWritten = 2
        ..committedAlready = 1;
      await pump(tester, s);

      expect(find.text('2 records were added.'), findsOneWidget);
      expect(find.text('1 row was already in the account and was skipped.'), findsOneWidget);
    });

    testWidgets('a refused commit says so in words and reloads the session', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed()
        ..defaultExpense = 'food'
        ..defaultIncome = 'salary';
      await pump(tester, s);
      s.failNext['POST /api/v1/import-sessions/s1/commit'] = (
        409,
        {'code': 'conflict', 'message': 'Row 1 cannot be written: SECRET server text'},
      );

      await tester.tap(_button('Import 3 rows'));
      await tester.pumpAndSettle();

      expect(find.textContaining('may not have been written'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      // The session is read again: a 409 may mean it ended meanwhile.
      expect(server.count('GET /api/v1/import-sessions/s1'), 2);
    });

    testWidgets('an expired session says so and offers the way back', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed()..state = 'IMPORT_SESSION_STATE_EXPIRED');

      expect(find.text('This import has expired'), findsOneWidget);
      expect(find.textContaining('kept for 24 hours'), findsOneWidget);
      expect(find.text('Back to import'), findsOneWidget);
      expect(find.byType(ZenSegmentedControl<Object>), findsNothing);
    });

    testWidgets('a session the server no longer knows reads as gone', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed();
      s.failNext['GET /api/v1/import-sessions/s1'] = (
        404,
        {'code': 'not_found', 'message': 'import session s1 not found'},
      );
      await pump(tester, s);

      expect(find.text('This import is no longer available'), findsOneWidget);
      expect(find.textContaining('not found'), findsNothing);
    });

    testWidgets('changing the destination previews again for the new account', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(
        tester,
        // Row 4 is a duplicate in Erste, and row 1 would be one in Savings.
        ImportServer(
          rows: _rows(),
          accountId: 'acc',
          duplicatesByAccount: {'acc': {4}, 'other': {1}},
        ),
        accounts: [_account('acc', 'Erste'), _account('other', 'Savings', number: 'PL00000000000000000000000002')],
      );
      // The choice made for the first account.
      await tester.tap(find.text('Duplicates (1)'));
      await tester.pumpAndSettle();
      tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow)).onChanged!(true);
      await tester.pumpAndSettle();
      expect(find.text('Import 4 rows'), findsOneWidget);
      // The cost of a change is said before it is made.
      expect(find.textContaining('Your "Import anyway" choices are reset'), findsOneWidget);

      _choose(tester, 'Destination account', 'other');
      await tester.pumpAndSettle();

      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/preview').last, {'accountId': 'other'});
      expect(find.text('Into Savings in PLN'), findsOneWidget);
      // Classified again for the new account, and the choice is gone.
      expect(find.text('Duplicates (1)'), findsOneWidget);
      expect(find.text('Import 3 rows'), findsOneWidget);
      expect(find.text('TEST CARD PAYMENT EXAMPLE'), findsOneWidget);
      expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow)).value, isFalse);
    });

    testWidgets('a refused destination is explained by its rule', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed();
      await pump(
        tester,
        s,
        accounts: [_account('acc', 'Erste'), _account('other', 'Savings', number: 'PL00000000000000000000000002')],
      );
      s.failNext['POST /api/v1/import-sessions/s1/preview'] = (
        400,
        {'code': 'invalid', 'message': 'The statement was rejected (account.identity_mismatch).'},
      );

      _choose(tester, 'Destination account', 'other');
      await tester.pumpAndSettle();

      expect(find.textContaining('belongs to a different account'), findsOneWidget);
      // Nothing changed: the rows and the destination are as the server last said.
      expect(find.text('Into Erste in PLN'), findsOneWidget);
    });

    testWidgets('discarding asks first, then discards and leaves', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.byWidgetPredicate((w) => w is ZenIconButton && w.label == 'Discard import'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this import?'), findsOneWidget);
      expect(server.count('POST /api/v1/import-sessions/s1/discard'), 0);

      await tester.tap(find.widgetWithText(ZenButton, 'Discard import'));
      await tester.pumpAndSettle();
      expect(server.count('POST /api/v1/import-sessions/s1/discard'), 1);
    });

    testWidgets('a narrow window still shows every group and the confirm bar', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed(), width: 360);

      expect(tester.takeException(), isNull);
      expect(find.text('Import 3 rows'), findsOneWidget);
      expect(find.text('TEST CARD PAYMENT EXAMPLE'), findsOneWidget);
    });
  });

  group('entry point', () {
    testWidgets('the accounts page offers the import and opens its first step', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, ImportServer(rows: _rows()), home: const AccountScreen());

      await tester.tap(find.byWidgetPredicate((w) => w is ZenIconButton && w.label == 'Import a statement'));
      await tester.pumpAndSettle();

      expect(find.text('Import a bank statement'), findsOneWidget);
      expect(find.text('Choose CSV file'), findsOneWidget);
    });
  });

  group('upload', () {
    PickedStatement file() => _file();

    ImportServer empty() => ImportServer(rows: _rows());

    testWidgets('uploads the chosen file for the chosen account and opens the review', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, empty(), home: const ImportStatementScreen(), picker: () async => file());

      expect(_enabled(tester, 'Check statement'), isFalse);
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(find.text('File: statement-example.csv'), findsOneWidget);

      // One active account is chosen for the user.
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();

      final sent = server.bodiesOf('POST /api/v1/import-sessions').single;
      expect(sent['formatId'], 'erste-pl-csv');
      expect(sent['accountId'], 'acc');
      expect(base64Decode(sent['content'] as String), utf8.encode('synthetic bytes'));
      // The review replaced the upload page.
      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('To import (3)'), findsOneWidget);
    });

    testWidgets('only active accounts are offered', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(
        tester,
        empty(),
        home: const ImportStatementScreen(),
        accounts: [_account('acc', 'Erste'), _account('old', 'Closed', active: false)],
      );
      await tester.tap(find.text('Choose CSV file'));
      expect(
        tester.widget<ZenSelect<String>>(_select('Destination account')).items,
        ['acc'],
      );
    });

    testWidgets('an account without a bank number is refused with a way to add it', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(
        tester,
        empty(),
        home: const ImportStatementScreen(),
        accounts: [_account('acc', 'Erste', number: '')],
        picker: () async => file(),
      );
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('no bank account number yet'), findsOneWidget);
      expect(find.text('Add account number'), findsOneWidget);
      expect(_enabled(tester, 'Check statement'), isFalse);
    });

    testWidgets('no active account says so', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(
        tester,
        empty(),
        home: const ImportStatementScreen(),
        accounts: [_account('old', 'Closed', active: false)],
      );
      expect(find.text('Add an active account to import a statement into.'), findsOneWidget);
    });

    testWidgets('an empty or oversized file is refused before it is sent', (tester) async {
      if (skipWithoutZenPlatform()) return;
      var next = PickedStatement(name: 'e.csv', bytes: Uint8List(0));
      await pump(tester, empty(), home: const ImportStatementScreen(), picker: () async => next);

      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This file is empty'), findsOneWidget);

      next = PickedStatement(name: 'big.csv', bytes: Uint8List(5 * 1024 * 1024 + 1));
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('larger than 5 MiB'), findsOneWidget);
      expect(server.count('POST /api/v1/import-sessions'), 0);
    });

    testWidgets('a rule refusal is explained with its rows and not by the server text', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = empty();
      s.failNext['POST /api/v1/import-sessions'] = (
        400,
        {
          'code': 'invalid',
          'message': 'The statement was rejected at rows 3, 5 and 2 more (amount.invalid).',
        },
      );
      await pump(tester, s, home: const ImportStatementScreen(), picker: () async => file());
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();

      expect(find.text('The statement was not accepted'), findsOneWidget);
      expect(find.textContaining('amount in a form that is not supported'), findsOneWidget);
      expect(find.text('Rows involved: 3, 5 and 2 more'), findsOneWidget);
      expect(find.textContaining('amount.invalid'), findsNothing);
      // Still on the upload page, and the file is kept for another try.
      expect(find.text('File: statement-example.csv'), findsOneWidget);
    });

    testWidgets('a rule this client does not know falls back to a generic sentence with its code', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = empty();
      s.failNext['POST /api/v1/import-sessions'] = (
        400,
        {'code': 'invalid', 'message': 'The statement was rejected at row 7 (future.rule_name).'},
      );
      await pump(tester, s, home: const ImportStatementScreen(), picker: () async => file());
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('code future.rule_name'), findsOneWidget);
      expect(find.text('Rows involved: 7'), findsOneWidget);
      expect(find.textContaining('The statement was rejected at row'), findsNothing);
    });

    testWidgets('a refusal with no rule is never shown as the server wrote it', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = empty();
      s.failNext['POST /api/v1/import-sessions'] = (
        400,
        {'code': 'invalid', 'message': 'TEST SECRET DESCRIPTION leaked into a message'},
      );
      await pump(tester, s, home: const ImportStatementScreen(), picker: () async => file());
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.textContaining('holds the statement\'s currency'), findsOneWidget);
    });

    testWidgets('too many open imports points at the unfinished ones', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = empty();
      s.failNext['POST /api/v1/import-sessions'] = (
        409,
        {'code': 'conflict', 'message': 'Too many import sessions are open.'},
      );
      await pump(tester, s, home: const ImportStatementScreen(), picker: () async => file());
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Too many imports are waiting'), findsOneWidget);
      expect(find.text('Unfinished imports'), findsOneWidget);
      expect(find.text('To import: 3, duplicates: 1, not readable: 2'), findsOneWidget);
    });

    testWidgets('an unfinished import can be continued', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, empty(), home: const ImportStatementScreen());

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Review import'), findsOneWidget);
    });
  });

  group('opened through showZenDetail', () {
    // At 1000 px the host is wide and the import is the root page of a side pane; at 500 it is a
    // pushed page. Everything below holds in both, because the import never replaces its own page.
    for (final width in [1000.0, 500.0]) {
      final wide = width >= zenDetailMinWidth;
      final where = wide ? 'in a pane' : 'as a pushed page';

      Future<void> open(WidgetTester tester, ImportServer s) async {
        await pump(
          tester,
          s,
          home: const ZenDetailHost(child: _Opener()),
          picker: () async => _file(),
          width: width,
        );
        await tester.tap(find.text('Open import'));
        await tester.pumpAndSettle();
      }

      Future<void> check(WidgetTester tester) async {
        await tester.tap(find.text('Choose CSV file'));
        await tester.pumpAndSettle();
        await tester.tap(_button('Check statement'));
        await tester.pumpAndSettle();
      }

      testWidgets('upload, review, confirm and result stay on one page $where', (tester) async {
        if (skipWithoutZenPlatform()) return;
        final s = ImportServer(rows: _rows())
          ..defaultExpense = 'food'
          ..defaultIncome = 'salary';
        await open(tester, s);
        expect(find.text('Import a bank statement'), findsOneWidget);

        await check(tester);
        // Checking the statement did not close the pane or leave the page.
        expect(tester.takeException(), isNull);
        expect(find.text('Review import'), findsOneWidget);
        expect(find.text('Import a bank statement'), findsNothing);

        await tester.tap(_button('Import 3 rows'));
        await tester.pumpAndSettle();
        expect(s.bodiesOf('POST /api/v1/import-sessions/s1/commit').single, {'confirmedAcceptedRows': 3});
        expect(find.text('3 records were added.'), findsOneWidget);

        await tester.tap(find.text('Back to accounts'));
        await tester.pumpAndSettle();
        expect(find.text('Import finished'), findsNothing);
        expect(find.text('List of accounts'), findsOneWidget);
        expect(s.count('POST /api/v1/import-sessions/s1/discard'), 0);
      });

      testWidgets('an import that ended returns to its first step, not to the list $where', (tester) async {
        if (skipWithoutZenPlatform()) return;
        final s = ImportServer(rows: _rows());
        await open(tester, s);
        s.failNext['GET /api/v1/import-sessions/s1'] = (
          404,
          {'code': 'not_found', 'message': 'import session s1 not found'},
        );
        // The unfinished session is listed under the upload step; Continue reads it and finds it gone.
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('This import is no longer available'), findsOneWidget);

        await tester.tap(find.text('Back to import'));
        await tester.pumpAndSettle();
        expect(find.text('Import a bank statement'), findsOneWidget);
        expect(find.text('Choose CSV file'), findsOneWidget);
      });

      testWidgets('the page\'s own Back asks first, and leaving discards $where', (tester) async {
        if (skipWithoutZenPlatform()) return;
        final s = ImportServer(rows: _rows());
        await open(tester, s);
        await check(tester);

        final navigator = Navigator.of(tester.element(find.byType(ImportPreviewScreen)));
        // The system's back, the browser's back and Navigator.maybePop all arrive here.
        final popped = navigator.maybePop();
        await tester.pumpAndSettle();
        expect(find.text('Leave this import?'), findsOneWidget);
        expect(s.count('POST /api/v1/import-sessions/s1/discard'), 0);

        await tester.tap(find.widgetWithText(ZenButton, 'Stay'));
        await tester.pumpAndSettle();
        expect(await popped, isTrue);
        expect(find.text('Review import'), findsOneWidget);
        expect(s.count('POST /api/v1/import-sessions/s1/discard'), 0);

        navigator.maybePop();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ZenButton, 'Discard and leave'));
        await tester.pumpAndSettle();
        expect(s.count('POST /api/v1/import-sessions/s1/discard'), 1);
        expect(find.text('Review import'), findsNothing);
        expect(find.text('List of accounts'), findsOneWidget);
      });
    }

    testWidgets('a pane\'s Close leaves the session open, and it is listed under unfinished imports', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = ImportServer(rows: _rows());
      await pump(
        tester,
        s,
        home: const ZenDetailHost(child: _Opener()),
        picker: () async => _file(),
        width: 1000,
      );
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Check statement'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);

      // The framework's Close dismisses the pane without consulting the page (ADR-093).
      await tester.tap(find.byWidgetPredicate((w) => w is ZenIconButton && w.label == 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsNothing);
      expect(s.count('POST /api/v1/import-sessions/s1/discard'), 0);

      // Open again: the unfinished import is there to continue.
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      expect(find.text('Unfinished imports'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('To import (3)'), findsOneWidget);
    });
  });

  group('committing', () {
    testWidgets('a statement with nothing to import can be finished without importing', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = ImportServer(
        rows: [
          importRow(1, status: duplicate, amount: -2000, description: 'TEST DUPLICATE PAYMENT', duplicateCode: 'duplicate.already_imported'),
          importRow(2, status: rejected, date: null, rejectionCode: 'description.unknown_shape'),
        ],
        accountId: 'acc',
      );
      await pump(tester, s);

      expect(find.text('To import (0)'), findsOneWidget);
      expect(_enabled(tester, 'Finish without importing'), isTrue);
      await tester.tap(_button('Finish without importing'));
      await tester.pumpAndSettle();

      expect(s.bodiesOf('POST /api/v1/import-sessions/s1/commit').single, {'confirmedAcceptedRows': 0});
      expect(find.text('No records were added.'), findsOneWidget);
    });

    testWidgets('a commit the network lost before the server saw it can be sent again unchanged', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed()
        ..defaultExpense = 'food'
        ..defaultIncome = 'salary';
      await pump(tester, s);
      s.dropBefore.add('POST /api/v1/import-sessions/s1/commit');

      await tester.tap(_button('Import 3 rows'));
      await tester.pumpAndSettle();
      expect(find.textContaining('may not have been written'), findsOneWidget);
      // The session was read again to show where it stands, and is still open.
      expect(s.count('GET /api/v1/import-sessions/s1'), 2);
      expect(find.text('Import 3 rows'), findsOneWidget);

      // Let the message go, so it does not cover the button.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(_button('Import 3 rows'));
      await tester.pumpAndSettle();
      expect(s.bodiesOf('POST /api/v1/import-sessions/s1/commit').single, {'confirmedAcceptedRows': 3});
      expect(find.text('3 records were added.'), findsOneWidget);
    });

    testWidgets('a commit whose answer was lost shows its result after the reload, written once', (tester) async {
      if (skipWithoutZenPlatform()) return;
      final s = previewed()
        ..defaultExpense = 'food'
        ..defaultIncome = 'salary';
      await pump(tester, s);
      s.dropResponse.add('POST /api/v1/import-sessions/s1/commit');

      await tester.tap(_button('Import 3 rows'));
      await tester.pumpAndSettle();

      expect(find.textContaining('may not have been written'), findsOneWidget);
      // The reload finds the commit went through: the result, and no second write.
      expect(find.text('3 records were added.'), findsOneWidget);
      expect(s.count('POST /api/v1/import-sessions/s1/commit'), 1);
    });

    testWidgets('a note alone can be saved on a row', (tester) async {
      if (skipWithoutZenPlatform()) return;
      await pump(tester, previewed());

      await tester.tap(find.text('TEST CARD PAYMENT EXAMPLE'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'for the record');
      await tester.tap(find.text('Save row'));
      await tester.pumpAndSettle();

      // Only what changed is sent: no category.
      expect(server.bodiesOf('POST /api/v1/import-sessions/s1/rows/1').single, {'note': 'for the record'});
      expect(find.text('Note: for the record'), findsOneWidget);
    });
  });
}
