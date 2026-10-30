// The analytics screen on a wide and a narrow window (jlogicsoftware/prudent#194): its content sits
// in a bounded column, the legend's rows are divided, and its text is no smaller than the body.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/analytics/analytics.dart';
import 'package:prudent/analytics/analytics_column.dart';
import 'package:prudent/analytics/analytics_view.dart';
import 'package:prudent/analytics/bar_chart_painter.dart';
import 'package:prudent/analytics/legend_row.dart';
import 'package:prudent/generated/prudent/v1/analytics.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class _Categories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => [
    Category(id: 'a', title: 'Food', colorArgb: 0xFF2E7D32),
    Category(id: 'b', title: 'Rent', colorArgb: 0xFF1565C0),
    Category(id: 'c', title: 'Travel', colorArgb: 0xFFC62828),
  ];
}

void main() {
  Future<void> pump(WidgetTester tester, double width, {ThemeMode mode = ThemeMode.light}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsCurrenciesProvider.overrideWithValue(const ['PLN']),
          categoriesProvider.overrideWith(_Categories.new),
          spendByPeriodProvider.overrideWith(
            (ref, params) async => SpendByPeriodResponse(
              periods: [PeriodSpend(period: month, amountMinor: Int64(12000))],
            ),
          ),
          spendByCategoryProvider.overrideWith(
            (ref, params) async => SpendByCategoryResponse(
              items: [
                CategorySpend(categoryId: 'a', amountMinor: Int64(5000)),
                CategorySpend(categoryId: 'b', amountMinor: Int64(4000)),
                CategorySpend(categoryId: 'c', amountMinor: Int64(1000)),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          themeMode: mode,
          theme: ThemeData(colorSchemeSeed: Colors.green),
          darkTheme: ThemeData(colorSchemeSeed: Colors.green, brightness: Brightness.dark),
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: const AnalyticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openByCategory(WidgetTester tester) async {
    await tester.tap(find.text('Spend by category').last);
    await tester.pumpAndSettle();
  }

  final barChart = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BarChartPainter);

  double bodySize(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AnalyticsColumn))).textTheme.bodyMedium!.fontSize!;

  for (final (name, width, expected) in [
    ('wide', 1600.0, AnalyticsColumn.maxWidth),
    ('narrow', 400.0, 400.0),
  ]) {
    group('$name window ($width px)', () {
      testWidgets('the content column is bounded and fills a narrow window', (tester) async {
        await pump(tester, width);
        final toggle = tester.getSize(find.byType(ZenSegmentedControl<AnalyticsView>)).width;
        final chart = tester.getSize(barChart).width;
        expect(toggle, lessThanOrEqualTo(expected));
        expect(chart, lessThanOrEqualTo(expected));
        if (width < AnalyticsColumn.maxWidth) {
          expect(chart, greaterThan(width - 40));
          expect(toggle, greaterThan(width - 40));
        } else {
          expect(chart, greaterThan(AnalyticsColumn.maxWidth - 40));
        }
      });

      testWidgets('legend rows are divided and keep name and figures within the column', (tester) async {
        await pump(tester, width);
        await openByCategory(tester);

        expect(find.byType(LegendRow), findsNWidgets(3));
        expect(find.descendant(of: find.byType(AnalyticsColumn), matching: find.byType(Divider)), findsNWidgets(2));
        for (final row in tester.widgetList<LegendRow>(find.byType(LegendRow))) {
          expect(row.label, isNotEmpty);
        }
        final left = tester.getTopLeft(find.text('Food')).dx;
        final right = tester.getTopRight(find.text('50.00 PLN')).dx;
        expect(right - left, lessThanOrEqualTo(expected));
      });

      testWidgets('legend text is no smaller than the body, in light and dark', (tester) async {
        for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
          await pump(tester, width, mode: mode);
          await openByCategory(tester);
          for (final text in ['Food', '50%', '50.00 PLN']) {
            final style = tester.widget<Text>(find.text(text)).style!;
            expect(style.fontSize, greaterThanOrEqualTo(bodySize(tester)), reason: text);
            expect(style.color, Theme.of(tester.element(find.text(text))).colorScheme.onSurface);
          }
        }
      });

      testWidgets('the bar chart labels are body-sized and the chart is bounded', (tester) async {
        await pump(tester, width);
        final painter =
            tester
                    .widgetList<CustomPaint>(find.byType(CustomPaint))
                    .map((p) => p.painter)
                    .whereType<BarChartPainter>()
                    .single;
        expect(painter.labelStyle.fontSize, greaterThanOrEqualTo(bodySize(tester)));
        expect(tester.getSize(barChart).width, lessThanOrEqualTo(expected));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
