// The statement import, driven through the real app against the real stack.
//
// `flutter test integration_test/app_import_test.dart -d <device>` builds the app for that device
// and runs this file INSIDE it (macOS, an iOS simulator, ...), talking to a live Quarkus server and
// a live Supabase. That is what the widget tests and the pure-Dart `e2e_test.dart` cannot see: the
// compiled runner, the platform plugins, the real session cookie and the real server answers. It
// signs up a throwaway user on the local stack (the user stays there; it is dev data), creates an
// account with a bank number, imports a synthetic statement, checks the records and the balance,
// imports the same file again and expects every row to be a duplicate, then leaves through the
// leave prompt.
//
// What it does NOT cover: the native file panel. `statementPickerProvider` is overridden with the
// file's bytes, because a native dialog cannot be driven from inside the app. The panel was only
// looked at by hand on an iOS simulator (ADR-098); the macOS panel has not been seen.
//
//   task run:supabase && task run:server        # in another terminal
//   cd client && flutter test integration_test/app_import_test.dart -d macos \
//     --dart-define=ZEN_ENV=local --dart-define=ZEN_PLATFORM=macos \
//     --dart-define=ZEN_API_URL=http://localhost:8085
//
// For a phone-sized device add `--dart-define=WIDE=false` and use `ZEN_PLATFORM=ios` (or
// `android`): the pane is then a pushed page and Back, not Escape, is the exit that asks.
//
// This file is not run by `task test:client` (that runs `test/`) and not by `task test:e2e` (that
// names `integration_test/e2e_test.dart`, a pure-Dart VM suite), so it needs no CI runner.
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prudent/app.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/imports/import_preview_screen.dart';
import 'package:prudent/imports/statement_picker.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:prudent/providers.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';
import 'package:zen_ui_identity/zen_ui_identity.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Synthetic: nine rows in the Erste layout (card, BLIK, own-account transfers, a salary, a rent
/// payment), none of it taken from a real statement. Six rows are importable; the salary and the
/// rent payment are an unsupported kind and the outgoing own-account transfer's wording has never
/// been seen, so the importer refuses all three (docs/erste-csv-contract.md). It holds amounts of
/// 1000 or more, which the one real export seen never did.
const _csv = r'''2026-01-31,01-01-2026,'00 0000 0000 0000 0000 0000 0001,JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO,PLN,"1,00","1715,85",30,
20-01-2026,20-01-2026,Przelew TEST OPŁATA ZA CZYNSZ 01/2026,ADMINISTRACJA TESTOWA PRÓBNA 3,00 0000 0000 0000 0000 0000 0012,"-1850,00","1715,85",27,
16-01-2026,16-01-2026,DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 7.10 PLN KOMUNIKACJA TESTOWA ŚWIĘTOKRZYSKA WARSZAWA,,,"-7,10","3565,85",24,
15-01-2026,15-01-2026,Zakup BLIK Test Payments Sp. z o.o. PRÓBNA 7 ref:00000000002,Test Payments Sp. z o.o. PRÓBNA 7,00 0000 0000 0000 0000 0000 0011,"-99,99","3572,95",21,
12-01-2026,12-01-2026,Przelew na rachunek własny,FIRMA TESTOWA JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO WOJ. TESTOWE,00 0000 0000 0000 0000 0000 0002,"250,00","3672,94",18,
10-01-2026,10-01-2026,DOP. VISA 000000******0000 PŁATNOŚĆ KARTĄ 1234.56 PLN SKLEP TESTOWY RTV KRAKÓW,,,"-1234,56","3422,94",15,
08-01-2026,08-01-2026,Przelew na rachunek własny,FIRMA TESTOWA JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO WOJ. TESTOWE,00 0000 0000 0000 0000 0000 0002,"-1500,00","4657,50",12,
05-01-2026,05-01-2026,Zakup BLIK SKLEP TESTOWY ONLINE Testowa 1 ref:00000000001,SKLEP TESTOWY ONLINE Testowa 1,00 0000 0000 0000 0000 0000 0010,"-30,00","6157,50",9,
03-01-2026,03-01-2026,Wynagrodzenie TEST SP. Z O.O. 01/2026,TEST SP. Z O.O. PRÓBNA 1,00 0000 0000 0000 0000 0000 0002,"5200,00","6187,50",6,
02-01-2026,02-01-2026,DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 12.50 PLN SKLEP TESTOWY SPOŻYWCZY ŁÓDŹ,,,"-12,50","987,50",3,
''';

/// Opening balance plus the six importable rows, in minor units.
const _openingBalance = 100000;
const _importedAmounts = <int>[-710, -9999, 25000, -123456, -3000, -1250];

/// Wide hosts show a detail beside its list and Escape closes it; narrow ones push a page.
const _wide = bool.fromEnvironment('WIDE', defaultValue: true);

Finder _iconButton(String label) => find.byWidgetPredicate((w) => w is ZenIconButton && w.label == label);

/// Pumps until [finder] matches, so a slow server answer is waited for rather than raced.
Future<void> _waitFor(WidgetTester tester, Finder finder, {int seconds = 20}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  final texts = [
    for (final e in find.byType(Text).evaluate())
      (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
  ].where((t) => t.trim().isNotEmpty).join(' | ');
  throw StateError('Timed out waiting for $finder. On screen: $texts');
}

/// Taps the icon button named [label] on the topmost page. While a page is still arriving the page
/// below can hold a button with the same label, so this settles first and takes the last match.
Future<void> _tapIcon(WidgetTester tester, String label) async {
  await _waitFor(tester, _iconButton(label));
  await tester.pumpAndSettle();
  await tester.tap(_iconButton(label).last);
}

/// Opens the import from the Accounts page, chooses the (injected) file and checks it.
Future<void> _checkStatement(WidgetTester tester) async {
  await _tapIcon(tester, 'Import a statement');
  await _waitFor(tester, find.text('Choose CSV file'));
  await tester.tap(find.text('Choose CSV file'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ZenButton, 'Check statement'));
  await _waitFor(tester, find.textContaining('Not readable ('));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a statement is imported, a repeat is all duplicates, and leaving asks first', (tester) async {
    await initializeDateFormatting();
    final session = createSessionClient();
    late final SupabaseIdentityRepository identity;
    Future<bool> recover() async => (await identity.refreshSession()).isSuccess;
    ZenClient client() => ZenClient(
      baseUrl: zenApiUrl,
      httpClient: session,
      language: () => 'en',
      recoverSession: recover,
    );
    identity = SupabaseIdentityRepository(client: client());
    final repo = PrudentRepository(client: client());

    final email = 'prudent-app-test-${DateTime.now().microsecondsSinceEpoch}@example.com';
    final registered = await identity.registerWithEmail(email: email, password: 'secret123');
    expect(registered.isSuccess, isTrue, reason: 'register: ${registered.errorOrNull?.message}');
    final account = await repo.createAccount(
      CreateAccountRequest(
        name: 'Erste test',
        type: AccountType.ACCOUNT_TYPE_CHECKING,
        isActive: true,
        includeInTotal: true,
        includeInOverview: true,
        balances: [CurrencyBalance(currency: 'PLN', amountMinor: Int64(_openingBalance))],
        accountNumber: '00 0000 0000 0000 0000 0000 0001',
      ),
    );
    expect(account.isSuccess, isTrue, reason: 'account: ${account.errorOrNull?.message}');
    final categories = (await repo.listCategories()).dataOrNull!.categories;
    expect(categories, isNotEmpty, reason: 'registration seeds the default categories');

    final container = ProviderContainer(
      overrides: [
        identityRepositoryProvider.overrideWithValue(identity),
        prudentRepositoryProvider.overrideWithValue(repo),
        sessionClientProvider.overrideWithValue(session),
        statementPickerProvider.overrideWithValue(
          () async => PickedStatement(name: 'history_20261115.csv', bytes: utf8.encode(_csv)),
        ),
      ],
    );
    addTearDown(container.dispose);
    if (_wide) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const PrudentApp()));
    await _waitFor(tester, find.text('Erste test'));

    // Overview -> Accounts -> Import: the import is a page above the Accounts pane (ADR-062).
    await _tapIcon(tester, 'Accounts');
    await _checkStatement(tester);
    expect(find.textContaining('To import (6)'), findsOneWidget);
    expect(find.textContaining('Not readable (3)'), findsOneWidget);

    // Each row needs a category: set the defaults for both directions, then confirm.
    final categoryId = categories.first.id;
    for (final label in ['Default category for expenses', 'Default category for income']) {
      tester
          .widget<ZenSelect<String>>(find.byWidgetPredicate((w) => w is ZenSelect<String> && w.label == label))
          .onChanged!(categoryId);
      await tester.pumpAndSettle();
    }
    final confirm = find.widgetWithText(ZenButton, 'Import 6 rows');
    expect(tester.widget<ZenButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await _waitFor(tester, find.text('6 records were added.'));

    final records = (await repo.listRecords()).dataOrNull!.records;
    expect(records.map((r) => r.amountMinor.toInt()).toList()..sort(), [..._importedAmounts]..sort());
    final balance = (await repo.listAccounts()).dataOrNull!.accounts.single.balances.single;
    expect(balance.currency, 'PLN');
    expect(
      balance.amountMinor.toInt(),
      _openingBalance + _importedAmounts.reduce((a, b) => a + b),
      reason: 'the imported records move the derived balance',
    );

    // The same file again: every importable row is already in the ledger.
    await tester.tap(find.widgetWithText(ZenButton, 'Back to accounts'));
    await tester.pumpAndSettle();
    await _checkStatement(tester);
    expect(find.textContaining('Duplicates (6)'), findsOneWidget);
    expect(find.textContaining('To import (0)'), findsOneWidget);
    expect((await repo.listRecords()).dataOrNull!.records, hasLength(6), reason: 'nothing was written twice');

    // The review is an open session, so leaving asks first. Wide: Escape (jZen#226, ADR-097);
    // narrow: Back. Stay keeps it, Discard and leave ends it.
    if (_wide) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } else {
      Navigator.of(tester.element(find.byType(ImportPreviewScreen))).maybePop();
    }
    await tester.pumpAndSettle();
    expect(find.text('Leave this import?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ZenButton, 'Stay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Duplicates (6)'), findsOneWidget);

    // Back, not a second Escape: after Stay the second Escape showed no prompt in this test
    // (focus after the dialog is unverified, ADR-098), and Back always reaches the same guard.
    Navigator.of(tester.element(find.byType(ImportPreviewScreen))).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ZenButton, 'Discard and leave'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Duplicates (6)'), findsNothing);
  });
}
