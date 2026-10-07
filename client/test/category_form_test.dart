// The category form (jlogicsoftware/prudent#103) on the framework's buttons, and its two domain
// grids — colour and icon — which stay Prudent's own but must be reachable by keyboard and show
// where focus is. What is asserted is what reaches onSave, and that a key press alone can pick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/category/category_color_swatch.dart';
import 'package:prudent/category/category_icon_choice.dart';
import 'package:prudent/category/category_icons.dart';
import 'package:prudent/category/new_category.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

class _Saved {
  _Saved(this.title, this.iconKey, this.description, this.colorArgb);
  final String title;
  final String iconKey;
  final String description;
  final int colorArgb;
}

void main() {
  _Saved? saved;

  Future<void> open(WidgetTester tester) async {
    saved = null;
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [...PrudentLocalizations.localizationsDelegates, zenWidgetsLocaleDelegate],
        supportedLocales: PrudentLocalizations.supportedLocales,
        home: Scaffold(
          body: NewCategory(
            onSave:
                ({required title, required iconKey, required description, required colorArgb}) =>
                    saved = _Saved(title, iconKey, description, colorArgb),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The ring [FocusRing] draws: a bordered box in the theme's primary colour.
  Finder ringWithin(Finder control) => find.descendant(
    of: control,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration &&
          decoration.shape == BoxShape.rectangle &&
          decoration.border is Border &&
          (decoration.border! as Border).top.width == zenFocusRingWidth;
    }),
  );

  /// Tabs until [target] holds focus, failing rather than looping if it never does.
  Future<void> tabTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final element = tester.element(target);
      if (_holdsFocus(element)) return;
    }
    fail('focus never reached $target');
  }

  group('buttons', () {
    testWidgets('are the framework\'s', (tester) async {
      await open(tester);
      expect(find.widgetWithText(ZenButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(ZenButton, 'Save Category'), findsOneWidget);
    });

    testWidgets('Save hands back what was typed, the default colour and the first icon', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), '  Groceries ');
      await tester.tap(find.widgetWithText(ZenButton, 'Save Category'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.title, 'Groceries');
      expect(saved!.iconKey, prudentCategoryIcons.keys.first);
      expect(saved!.colorArgb, Colors.black.toARGB32());
    });

    testWidgets('an empty title is refused with a dialog whose OK is a framework button', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(ZenButton, 'Save Category'));
      await tester.pumpAndSettle();

      expect(saved, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      final ok = find.descendant(of: find.byType(AlertDialog), matching: find.byType(ZenButton));
      expect(ok, findsOneWidget);

      await tester.tap(ok);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('colour and icon grids', () {
    testWidgets('a tap still picks a colour and an icon', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rent');
      await tester.tap(find.byType(CategoryColorSwatch).at(2));
      await tester.tap(find.byType(CategoryIconChoice).at(1));
      await tester.tap(find.widgetWithText(ZenButton, 'Save Category'));
      await tester.pumpAndSettle();

      expect(saved!.colorArgb, prudentCategoryColors[2].toARGB32());
      expect(saved!.iconKey, prudentCategoryIcons.keys.elementAt(1));
    });

    testWidgets('a colour can be reached and picked with the keyboard alone, and shows a focus ring', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rent');
      final swatch = find.byType(CategoryColorSwatch).at(3);
      expect(ringWithin(swatch), findsNothing);

      await tabTo(tester, swatch);
      expect(ringWithin(swatch), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.tap(find.widgetWithText(ZenButton, 'Save Category'));
      await tester.pumpAndSettle();

      expect(saved!.colorArgb, prudentCategoryColors[3].toARGB32());
    });

    testWidgets('an icon can be reached and picked with the keyboard alone, and shows a focus ring', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rent');
      final choice = find.byType(CategoryIconChoice).at(2);
      expect(ringWithin(choice), findsNothing);

      await tabTo(tester, choice);
      expect(ringWithin(choice), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.tap(find.widgetWithText(ZenButton, 'Save Category'));
      await tester.pumpAndSettle();

      expect(saved!.iconKey, prudentCategoryIcons.keys.elementAt(2));
    });
  });
}

/// Whether focus sits on, or anywhere below, the widget [element] belongs to.
bool _holdsFocus(Element element) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  var found = false;
  void visit(Element e) {
    if (found) return;
    if (identical(e, focused)) {
      found = true;
      return;
    }
    e.visitChildren(visit);
  }

  visit(element);
  return found;
}
