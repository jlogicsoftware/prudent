// The categories screen run on an in-memory PrudentRepository, with no transport and no HTTP mock
// behind it (jlogicsoftware/prudent#245, unit 1): the proof that screens depend on the interface
// and not on the server implementation. The screen, its provider and the notifier are the real ones.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prudent_ui/category/categories_screen.dart';
import 'package:prudent_ui/generated/prudent/v1/categories.pb.dart';
import 'package:prudent_ui/l10n/generated/prudent_localizations.dart';
import 'package:prudent_ui/load_error_view.dart';
import 'package:prudent_ui/providers.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../fake_prudent_repository.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    FakePrudentRepository repository,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prudentRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            ...GlobalMaterialLocalizations.delegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: const CategoriesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the categories the repository answers with', (
    tester,
  ) async {
    final repository = FakePrudentRepository(
      categories: [
        Category(id: 'a', title: 'Groceries', iconKey: 'food'),
        Category(id: 'b', title: 'Rent', iconKey: 'work'),
      ],
    );

    await pump(tester, repository);

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(repository.listCategoriesCalls, 1);
  });

  testWidgets('shows the empty state when there are none', (tester) async {
    await pump(tester, FakePrudentRepository());

    expect(
      find.text(
        PrudentLocalizations.of(tester.element(find.byType(CategoriesScreen)))
            .categoriesEmpty,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a failed load shows the load error, and Try again asks the repository again',
    (tester) async {
      final repository = FakePrudentRepository()
        ..listCategoriesFailure = const ZenUnknownError('down');

      await pump(tester, repository);

      expect(find.byType(LoadErrorView), findsOneWidget);
      expect(
        find.textContaining('down'),
        findsNothing,
        reason: 'the error text is logged, never shown',
      );

      // Riverpod retries a failed provider on its own, so the count before Try again is not 1.
      final callsBeforeRetry = repository.listCategoriesCalls;
      repository.listCategoriesFailure = null;
      repository.categories.add(
        Category(id: 'a', title: 'Groceries', iconKey: 'food'),
      );
      await tester.tap(find.byType(ZenButton));
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);
      expect(repository.listCategoriesCalls, greaterThan(callsBeforeRetry));
    },
  );
}
