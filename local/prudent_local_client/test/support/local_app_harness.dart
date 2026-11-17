import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_local_client/app/local_composition.dart';
import 'package:prudent_local_client/app/local_providers.dart';
import 'package:prudent_local_client/app/prudent_local_app.dart';
import 'package:prudent_local_client/core/local_session.dart';
import 'package:prudent_local_client/repository/local_data_export.dart';
import 'package:prudent_ui/notification/notification_providers.dart';
import 'package:prudent_ui/providers.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

import 'two_local_devices.dart';
import 'unsupported_gateway.dart';

/// The whole Prudent Local app on one device, composed exactly as `main` composes it
/// ([localOverrides]), driven through its screens.
///
/// File I/O never completes under a widget test's fake clock, so every step that reaches the disk
/// runs inside `runAsync` and is followed by pumps ([settle]).
final class LocalAppHarness {
  final WidgetTester tester;
  final LocalSession session;
  final ZenPinLock lock;
  final ZenLockStorage storage;

  LocalAppHarness._(this.tester, this.session, this.lock, this.storage);

  /// Pumps the app over [session]. [firstRunSeen] skips the one-time notice; [locale] picks the
  /// language; [overrides] add to (and win over) the app's own composition.
  static Future<LocalAppHarness> pump(
    WidgetTester tester,
    LocalSession session, {
    ZenLockStorage? storage,
    bool firstRunSeen = true,
    Locale locale = const Locale('en'),
    bool ownerCheck = false,
    List overrides = const [],
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final secrets = storage ?? ZenMemoryLockStorage();
    if (firstRunSeen) {
      await tester.runAsync(() => secrets.write(firstRunSeenKey, '1'));
    }
    final lock = (await tester.runAsync(
      () => ZenPinLock.load(storage: secrets, iterations: 1),
    ))!.dataOrNull!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...localOverrides(
            session: session,
            lock: lock,
            storage: secrets,
            export: LocalDataExport(now: () => DateTime.utc(2026, 11, 16, 9)),
          ),
          ownerCheckAvailableProvider.overrideWith((ref) async => ownerCheck),
          // The device notifications are unit 6b's; a test host has no notification plugin.
          localNotificationGatewayProvider.overrideWithValue(
            const UnsupportedGatewayForTests(),
          ),
          ...overrides.cast(),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ref.read(localeProvider) != locale) {
                ref.read(localeProvider.notifier).setLocale(locale);
              }
            });
            return const PrudentLocalApp();
          },
        ),
      ),
    );
    final harness = LocalAppHarness._(tester, session, lock, secrets);
    await harness.settle();
    return harness;
  }

  /// Lets the writes and syncs a tap started finish, then shows the result. Real time and pumps
  /// alternate, enough times for a write's several steps and a page transition. Not
  /// `pumpAndSettle`: a progress indicator never settles.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Settles until [finder] finds something, at most [rounds] times: a step that reopens a store or
  /// restarts sync takes many turns of I/O, and touching the store from the test before it is done
  /// would wait on work that only the test's pumps can finish.
  Future<void> settleUntil(Finder finder, {int rounds = 40}) async {
    for (var i = 0; i < rounds && finder.evaluate().isEmpty; i++) {
      await settle();
    }
    expect(finder, findsWidgets);
  }

  Future<void> tapText(String text) => tapFinder(find.text(text));

  /// Opens the tab [label]: directly where the navigation shows it (the desktop sidebar), or through
  /// the phone bar's "More" where it does not (`zen_ui_navigation` shows four tabs and More there).
  Future<void> openTab(String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await tapText(lookupNavigationLocalizations(const Locale("en")).more);
    }
    await tapText(label);
  }

  /// Taps [finder] on the real event loop and lets real time pass, for a button whose handler
  /// closes, erases and reopens the store: that work waits on file I/O and locks the fake clock
  /// never releases, which is why jZen's own tests call it inside `runAsync`.
  Future<void> tapReal(
    Finder finder, {
    Duration wait = const Duration(seconds: 2),
  }) async {
    final target = finder.first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(wait);
    });
    await settle();
  }

  Future<void> tapFinder(Finder finder) async {
    final target = finder.first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await settle();
  }

  /// Runs [step] on the real event loop (file I/O), then lets the app catch up.
  Future<T> run<T>(Future<T> Function() step) async {
    final result = await tester.runAsync(step);
    await settle();
    return result as T;
  }
}

/// Opens two devices for a widget test, closed again at its end.
Future<TwoLocalDevices> twoDevices(
  WidgetTester tester, [
  TransportKind kind = TransportKind.folderCloud,
]) async {
  final devices = (await tester.runAsync(() => TwoLocalDevices.create(kind)))!;
  addTearDown(() => tester.runAsync(devices.dispose));
  return devices;
}
