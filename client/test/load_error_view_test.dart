// A screen that cannot load its data (jlogicsoftware/prudent#160): a sentence in the user's own
// language, what to try, and a button that asks again — never the exception's text, which on the
// first persistent deploy was `ZenTransportError(code: internal_error, message: …)` in English
// whatever the language. The detail is logged, not shown.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/account/account_list.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/load_error_view.dart';
import 'package:prudent/providers.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

const _rawError = 'ZenTransportError(code: internal_error, message: Something went wrong.)';

Widget _app(Widget home, {List<Override> overrides = const [], Locale? locale}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: [...PrudentLocalizations.localizationsDelegates, zenWidgetsLocaleDelegate],
    supportedLocales: PrudentLocalizations.supportedLocales,
    home: Scaffold(body: home),
  ),
);

/// Fails on the first build, answers an empty list on every later one.
class _FlakyAccounts extends AccountsNotifier {
  int builds = 0;

  @override
  Future<List<Account>> build() async {
    builds++;
    if (builds == 1) throw StateError(_rawError);
    return const [];
  }
}

void main() {
  testWidgets('shows the sentence and the hint, and never the exception', (tester) async {
    await tester.pumpWidget(
      _app(
        LoadErrorView(message: 'Could not load accounts.', error: StateError(_rawError), onRetry: () {}),
      ),
    );

    expect(find.text('Could not load accounts.'), findsOneWidget);
    expect(find.text('Something went wrong. Check your connection and try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('ZenTransportError'), findsNothing);
    expect(find.textContaining('internal_error'), findsNothing);
  });

  testWidgets('the retry button asks again', (tester) async {
    var asked = 0;
    await tester.pumpWidget(
      _app(
        LoadErrorView(message: 'Could not load goals.', error: StateError('x'), onRetry: () => asked++),
      ),
    );

    await tester.tap(find.text('Try again'));
    expect(asked, 1);
  });

  testWidgets('the compact form keeps the sentence and the button, without the icon', (tester) async {
    await tester.pumpWidget(
      _app(
        LoadErrorView(
          message: 'Could not load the history.',
          error: StateError('x'),
          onRetry: () {},
          compact: true,
        ),
      ),
    );

    expect(find.text('Could not load the history.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('is shown in the user\'s language', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => LoadErrorView(
            message: PrudentLocalizations.of(context).accountsLoadError,
            error: StateError(_rawError),
            onRetry: () {},
          ),
        ),
        locale: const Locale('uk'),
      ),
    );

    expect(find.text('Не вдалося завантажити рахунки.'), findsOneWidget);
    expect(find.text('Спробувати ще раз'), findsOneWidget);
    expect(find.textContaining('ZenTransportError'), findsNothing);
  });

  testWidgets('a real screen: a failed load shows it, and Try again loads it again', (tester) async {
    final notifier = _FlakyAccounts();
    await tester.pumpWidget(
      _app(const AccountList(), overrides: [accountsProvider.overrideWith(() => notifier)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load accounts.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('internal_error'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(notifier.builds, 2);
    expect(find.text('No accounts added yet.'), findsOneWidget);
    expect(find.byType(LoadErrorView), findsNothing);
  });

  // The rule as a gate: no screen interpolates an exception into what the user reads. Both halves
  // are checked, because either one alone lets it come back — a string that takes `{error}`, or a
  // call site that passes `error.toString()`.
  test('no *LoadError string takes the exception, and no screen passes it on', () {
    for (final locale in ['en', 'uk', 'pl']) {
      final arb = File('lib/l10n/prudent_$locale.arb').readAsStringSync();
      expect(arb, isNot(contains('{error}')), reason: 'prudent_$locale.arb interpolates an exception');
    }
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !f.path.contains('/generated/') &&
            f.readAsStringSync().contains('error.toString()'))
          f.path,
    ];
    expect(offenders, isEmpty, reason: 'these pass an exception\'s text to the user: $offenders');
  });
}
