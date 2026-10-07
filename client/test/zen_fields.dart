import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// The text input labelled [label], whichever idiom the host platform draws.
///
/// `ZenTextField` is a `TextField` on Material and a Cupertino field on iOS and macOS, chosen by a
/// compile-time constant, so a suite that looks for `TextField` passes on a Linux runner and fails
/// on a Mac. `ZenAmountField` builds on `ZenTextField`, so this finds an amount field too.
Finder textInput(String label) =>
    find.byWidgetPredicate((widget) => widget is ZenTextField && widget.label == label);

/// The text currently in the input [field] (see [textInput]), read from its editable text so it
/// does not depend on which idiom drew it.
String textOf(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
    .controller
    .text;

/// The icon button named [label]. `ZenIconButton` shows [label] as a tooltip on Material and only
/// as its accessible name on Cupertino, so `find.byTooltip` finds it on one idiom and not the other.
Finder iconButton(String label) =>
    find.byWidgetPredicate((widget) => widget is ZenIconButton && widget.label == label);
