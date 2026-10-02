import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Prudent's own Polish for `zen_ui_widgets`' controls (an amount or date field's error, its
/// placeholder, the wheel picker's confirm), supplied without jZen shipping `pl` (jZen ADR-044).
/// DELETE THIS FILE the day jZen ships `pl` for `zen_ui_widgets`.
class PlWidgetsLocalizations extends ZenWidgetsLocalizationsEn {
  PlWidgetsLocalizations() : super('pl');

  @override
  String get invalidAmount => 'Wpisz poprawną kwotę';

  @override
  String get invalidAmountRange => 'Minimum nie może być większe niż maksimum';

  @override
  String get invalidDateRange => 'Data początkowa nie może być późniejsza niż końcowa';

  @override
  String get selectDate => 'Wybierz datę';

  @override
  String get clearDate => 'Wyczyść datę';

  @override
  String get done => 'Gotowe';
}
