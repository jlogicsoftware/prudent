// "Move my data in" (unit 10b; ADR-103, ADR-123): the server's export, from a file the person picks,
// moved into this device's empty store whole, or refused with the reason on the page — in en, uk and
// pl — and nothing written.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_local_client/move_in/export_file_picker.dart';
import 'package:prudent_local_store/prudent_local_store.dart' show MoveInRule;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';

/// A small synthetic export as the server writes it (ADR-088: nothing real): one account whose
/// balance is its opening, 1000.00 PLN, less one expense of 12.50.
Uint8List _exportFile() {
  const account = '00000000-0000-4000-8000-000000000001';
  const category = '00000000-0000-4000-8000-000000000002';
  final export = wire.DataExport(
    formatVersion: 1,
    exportedAtMs: Int64(1794830400000),
    settings: wire.Settings(mainCurrency: 'PLN'),
    accounts: [
      wire.Account(
        id: account,
        name: 'Moved wallet',
        type: wire.AccountType.ACCOUNT_TYPE_CASH,
        isDefault: true,
        isActive: true,
        includeInTotal: true,
        includeInOverview: true,
        balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(98750))],
      ),
    ],
    categories: [wire.Category(id: category, title: 'Food', iconKey: 'food')],
    records: [
      wire.Record(
        id: '00000000-0000-4000-8000-000000000003',
        title: 'Bread',
        amountMinor: Int64(-1250),
        currency: 'PLN',
        date: '2026-11-02',
        accountId: account,
        categoryId: category,
      ),
    ],
  );
  return utf8.encode(jsonEncode(export.toProto3Json()));
}

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  Future<LocalAppHarness> openMoveIn(
    WidgetTester tester,
    Future<Uint8List?> Function() picker, {
    bool withData = false,
    Locale locale = const Locale('en'),
  }) async {
    final devices = await twoDevices(tester);
    if (withData) {
      await tester.runAsync(() => openBooks(devices.phone.ledger));
    }
    final app = await LocalAppHarness.pump(
      tester,
      devices.phone,
      locale: locale,
      overrides: [exportFilePickerProvider.overrideWithValue(picker)],
    );
    final tt = lookupPrudentLocalizations(locale);
    final ll = lookupLocalLocalizations(locale);
    await app.openTab(tt.navSettings);
    await app.tapText(tt.settingsPrivacy);
    // The entry sits last on the page, below the erasures; the list builds it once scrolled to.
    await tester.scrollUntilVisible(
      find.text(ll.moveInEntryHint),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await app.tapFinder(find.text(ll.moveInTitle).last);
    return app;
  }

  testWidgets('an export moves into the empty store, and its balance is the file\'s', (
    tester,
  ) async {
    final app = await openMoveIn(tester, () async => _exportFile());
    // The warning and the server note are on the page before anything is chosen.
    expect(find.text(l.moveInFileWarning), findsOneWidget);
    expect(find.text(l.moveInServerNote), findsOneWidget);

    await app.tapReal(find.text(l.moveInButton));
    await app.settleUntil(find.text(l.moveInDone(1, 1, 0, 0, 0, 0)));
    // What was checked, and what was not moved, are said beside the counts (review N2 on #273).
    expect(find.text(l.moveInChecked), findsOneWidget);
    expect(find.text(l.moveInNotMoved), findsOneWidget);

    final accounts = (await tester.runAsync(() => app.session.ledger.listAccounts()))!;
    final listed = ok(accounts).value.accounts.single;
    expect(listed.name, 'Moved wallet');
    expect(listed.isDefault, isTrue);
    expect(listed.balances.single.amountMinor, Int64(98750));
  });

  testWidgets('a device that already holds data refuses it, says why, and writes nothing', (
    tester,
  ) async {
    final app = await openMoveIn(tester, () async => _exportFile(), withData: true);
    await app.tapReal(find.text(l.moveInButton));
    await app.settleUntil(find.text(l.moveInStoreNotEmpty));
    expect(find.text(l.moveInRefused), findsOneWidget);
    expect(find.text(l.moveInDetails(MoveInRule.storeNotEmpty.code)), findsOneWidget);
    final accounts = (await tester.runAsync(() => app.session.ledger.listAccounts()))!;
    expect(ok(accounts).value.accounts.map((a) => a.name), isNot(contains('Moved wallet')));
  });

  testWidgets('a file that is not an export is refused', (tester) async {
    final app = await openMoveIn(tester, () async => Uint8List.fromList(utf8.encode('{"x": 1}')));
    await app.tapReal(find.text(l.moveInButton));
    await app.settleUntil(find.text(l.moveInUnreadable));
    expect(find.text(l.moveInRefused), findsOneWidget);
  });

  testWidgets('a file too large is not read', (tester) async {
    final app = await openMoveIn(tester, () async => throw const ExportFileTooLarge());
    await app.tapReal(find.text(l.moveInButton));
    await app.settleUntil(find.text(l.moveInTooLarge));
  });

  testWidgets('a cancelled pick says nothing', (tester) async {
    final app = await openMoveIn(tester, () async => null);
    await app.tapReal(find.text(l.moveInButton));
    expect(find.text(l.moveInRefused), findsNothing);
    expect(find.textContaining(l.moveInDetails('')), findsNothing);
  });

  for (final locale in const [Locale('uk'), Locale('pl')]) {
    testWidgets('the refusal is said in ${locale.languageCode}', (tester) async {
      final ll = lookupLocalLocalizations(locale);
      final app = await openMoveIn(
        tester,
        () async => _exportFile(),
        withData: true,
        locale: locale,
      );
      await app.tapReal(find.text(ll.moveInButton));
      await app.settleUntil(find.text(ll.moveInStoreNotEmpty));
      expect(find.text(ll.moveInRefused), findsOneWidget);
      expect(t.navSettings, isNotEmpty);
    });
  }
}
