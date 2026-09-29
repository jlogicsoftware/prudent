import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/popup.dart';

/// Prudent's side of the overlay contract: `Popup` opens its body through the framework's
/// adaptive presentation, and what closes it is the caller's own `Navigator.pop`. Which chrome
/// (sheet or dialog, Cupertino or Material) each platform gets is `zen_ui_widgets`' to test — it is
/// a compile-time constant, so a suite only ever sees the host's branch — so this asserts only
/// that the wiring is intact.
void main() {
  testWidgets('tapping a Popup shows its body and the body can dismiss it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Popup(
            popupLeading: const Icon(Icons.add),
            popupBody: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('body'),
                  ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('body'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);

    await tester.tap(find.text('body'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
  });
}
