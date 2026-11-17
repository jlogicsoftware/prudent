// The person's data copy (plan unit 9; ADR-100 T14, T22): a file they pick the place of through
// zen_save_file, never the clipboard; warned about before the button; the server's document shape;
// a file name with a date and nothing of the ledger in it.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/l10n/generated/local_localizations.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';

import 'support/ledger_setup.dart';
import 'support/local_app_harness.dart';

void main() {
  final t = lookupPrudentLocalizations(const Locale('en'));
  final l = lookupLocalLocalizations(const Locale('en'));

  testWidgets(
    'the copy is a chosen file of the whole ledger, warned about first, never the clipboard',
    (tester) async {
      final devices = await twoDevices(tester);
      await tester.runAsync(() async {
        final books = await openBooks(devices.phone.ledger);
        await addRecord(devices.phone.ledger, books);
      });
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      String? savedName;
      Uint8List? savedBytes;
      final app = await LocalAppHarness.pump(
        tester,
        devices.phone,
        overrides: [
          saveFileProvider.overrideWithValue((name, bytes) async {
            savedName = name;
            savedBytes = bytes;
            return true;
          }),
        ],
      );
      await app.openTab(t.navSettings);
      await app.tapText(t.settingsPrivacy);

      // The warning is above the button, on screen before anything is pressed.
      final warning = tester.getTopLeft(find.text(l.dataCopyWarning));
      final button = tester.getTopLeft(find.text(l.dataCopyButton));
      expect(warning.dy, lessThan(button.dy));

      await app.tapText(l.dataCopyButton);
      expect(find.text(l.dataCopySaved), findsWidgets);
      expect(savedName, 'prudent-export-2026-11-16.json');
      final document =
          jsonDecode(utf8.decode(savedBytes!)) as Map<String, dynamic>;
      expect(document['formatVersion'], 1);
      expect((document['accounts'] as List).single['name'], 'Wallet');
      expect((document['categories'] as List).single['title'], 'Food');
      expect((document['records'] as List).single['title'], 'Bread');
      expect(document.containsKey('profile'), isFalse);
      expect(platformCalls.where((m) => m.startsWith('Clipboard')), isEmpty);
    },
  );

  testWidgets('a cancelled save says nothing and writes nothing', (
    tester,
  ) async {
    final devices = await twoDevices(tester);
    final app = await LocalAppHarness.pump(
      tester,
      devices.phone,
      overrides: [
        saveFileProvider.overrideWithValue((name, bytes) async => false),
      ],
    );
    await app.openTab(t.navSettings);
    await app.tapText(t.settingsPrivacy);
    await app.tapText(l.dataCopyButton);
    expect(find.text(l.dataCopySaved), findsNothing);
    expect(find.text(l.dataCopyFailed), findsNothing);
  });

  testWidgets('a refused write says it failed', (tester) async {
    final devices = await twoDevices(tester);
    final app = await LocalAppHarness.pump(
      tester,
      devices.phone,
      overrides: [
        saveFileProvider.overrideWithValue(
          (name, bytes) async => throw const FormatException('disk'),
        ),
      ],
    );
    await app.openTab(t.navSettings);
    await app.tapText(t.settingsPrivacy);
    await app.tapText(l.dataCopyButton);
    expect(find.text(l.dataCopyFailed), findsWidgets);
  });
}
