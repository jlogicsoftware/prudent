// The category grid sizes itself from the width it is given (jlogicsoftware/prudent#104), not from
// a platform constant: `zenIsDesktop` is false on every web build, so a wide browser window used to
// get the phone's two columns. The breakpoint is the framework's zenNarrowWidth.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/category/categories_screen.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class _FixedCategories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => [
    for (var i = 0; i < 6; i++) Category(id: 'c$i', title: 'Category $i', iconKey: 'work'),
  ];
}

void main() {
  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [categoriesProvider.overrideWith(_FixedCategories.new)],
        child: MaterialApp(
          localizationsDelegates: [...PrudentLocalizations.localizationsDelegates, zenWidgetsLocaleDelegate],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: const CategoriesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SliverGridDelegateWithFixedCrossAxisCount delegateOf(WidgetTester tester) =>
      tester.widget<GridView>(find.byType(GridView)).gridDelegate
          as SliverGridDelegateWithFixedCrossAxisCount;

  testWidgets('a narrow width gets two compact columns', (tester) async {
    await pumpAt(tester, zenNarrowWidth - 1);

    expect(delegateOf(tester).crossAxisCount, 2);
    expect(delegateOf(tester).mainAxisExtent, 150);
  });

  testWidgets('a wide width gets three roomy columns, whatever the platform', (tester) async {
    await pumpAt(tester, 1200);

    expect(delegateOf(tester).crossAxisCount, 3);
    expect(delegateOf(tester).mainAxisExtent, 200);
  });

  testWidgets('the breakpoint is zenNarrowWidth itself, and resizing re-sizes the grid', (tester) async {
    await pumpAt(tester, zenNarrowWidth.toDouble());
    expect(delegateOf(tester).crossAxisCount, 3);

    tester.view.physicalSize = Size(zenNarrowWidth - 1, 900);
    await tester.pumpAndSettle();
    expect(delegateOf(tester).crossAxisCount, 2);
  });
}
