// The currency pick on the analytics and chart screens (jlogicsoftware/prudent#103), now a
// ZenSelect in the body rather than a DropdownButton in the app bar: it is offered only when more
// than one currency is held, and choosing one re-queries for that currency — never a blend.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/analytics/analytics.dart';
import 'package:prudent/analytics/chart_screen.dart';
import 'package:prudent/generated/prudent/v1/analytics.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class _FixedCategories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => const [];
}

void main() {
  final byPeriod = <String>[];
  final byCategory = <String>[];

  setUp(() {
    byPeriod.clear();
    byCategory.clear();
  });

  Future<void> pump(WidgetTester tester, Widget screen, List<String> currencies) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsCurrenciesProvider.overrideWithValue(currencies),
          categoriesProvider.overrideWith(_FixedCategories.new),
          spendByPeriodProvider.overrideWith((ref, params) async {
            byPeriod.add(params.currency);
            return SpendByPeriodResponse();
          }),
          spendByCategoryProvider.overrideWith((ref, params) async {
            byCategory.add(params.currency);
            return SpendByCategoryResponse();
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: [...PrudentLocalizations.localizationsDelegates, zenWidgetsLocaleDelegate],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AnalyticsScreen', () {
    testWidgets('offers a labelled currency select, starting on the first currency', (tester) async {
      await pump(tester, const AnalyticsScreen(), ['PLN', 'EUR']);

      final select = tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>));
      expect(select.label, 'Currency');
      expect(select.items, ['PLN', 'EUR']);
      expect(select.value, 'PLN');
      expect(byPeriod, ['PLN']);
      // The pick sits in the body, not squeezed into the app bar.
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(ZenSelect<String>)),
        findsNothing,
      );
    });

    testWidgets('choosing a currency loads that currency', (tester) async {
      await pump(tester, const AnalyticsScreen(), ['PLN', 'EUR']);

      tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).onChanged!('EUR');
      await tester.pumpAndSettle();

      expect(byPeriod, ['PLN', 'EUR']);
      expect(tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>)).value, 'EUR');
    });

    testWidgets('offers no select when only one currency is held', (tester) async {
      await pump(tester, const AnalyticsScreen(), ['PLN']);

      expect(find.byType(ZenSelect<String>), findsNothing);
      expect(byPeriod, ['PLN']);
    });
  });

  group('ChartScreen', () {
    testWidgets('offers a labelled currency select and choosing one loads that currency', (tester) async {
      await pump(tester, const ChartScreen(), ['PLN', 'EUR']);

      final select = tester.widget<ZenSelect<String>>(find.byType(ZenSelect<String>));
      expect(select.label, 'Currency');
      expect(select.value, 'PLN');
      expect(byCategory, ['PLN']);

      select.onChanged!('EUR');
      await tester.pumpAndSettle();

      expect(byCategory, ['PLN', 'EUR']);
    });

    testWidgets('offers no select when only one currency is held', (tester) async {
      await pump(tester, const ChartScreen(), ['PLN']);

      expect(find.byType(ZenSelect<String>), findsNothing);
    });
  });
}
