import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/record/records_list.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class Categories extends CategoriesNotifier {
  @override
  Future<List<Category>> build() async => [];
}

void main() {
  test('destructive theme colors remain readable in both themes', () {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: brightness,
      );
      final foreground = scheme.onErrorContainer.computeLuminance();
      final background = scheme.errorContainer.computeLuminance();
      final lighter = foreground > background ? foreground : background;
      final darker = foreground < background ? foreground : background;
      expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('record actions require confirmation and fit a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var removed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [categoriesProvider.overrideWith(Categories.new)],
        child: MaterialApp(
          localizationsDelegates: [
            ...PrudentLocalizations.localizationsDelegates,
            zenWidgetsLocaleDelegate,
          ],
          supportedLocales: PrudentLocalizations.supportedLocales,
          home: Scaffold(
            body: RecordsList(
              records: [
                Record(
                  id: '1',
                  title: 'Coffee',
                  date: '2026-10-29',
                  currency: 'EUR',
                ),
              ],
              onRemoveRecord: (_) => removed++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (zenIsMobile) {
      final actions =
          tester
              .widget<ZenListItemActions>(find.byType(ZenListItemActions))
              .actions;
      expect(actions[0].variant, ZenListItemActionVariant.standard);
      expect(actions[1].variant, ZenListItemActionVariant.destructive);
      expect(find.byType(ZenIconButton), findsNothing);
      await tester.drag(find.text('Coffee'), const Offset(-250, 0));
    } else if (zenIsWeb) {
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Delete record'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Delete record'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 650));
      await mouse.moveTo(tester.getCenter(find.text('Coffee')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Delete record'), findsOneWidget);
      semantics.dispose();
    } else if (!zenIsDesktop) {
      await tester.tap(find.byTooltip('Show record actions'));
    }
    await tester.pumpAndSettle();
    if (!zenIsMobile) {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ZenIconButton && widget.label == 'Delete record',
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Delete this record?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(removed, 0);
    if (zenIsMobile) {
      await tester.drag(find.text('Coffee'), const Offset(-250, 0));
    } else {
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ZenIconButton && widget.label == 'Delete record',
        ),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete record').last);
    await tester.pumpAndSettle();
    expect(removed, 1);
    expect(tester.takeException(), isNull);
  });
}
