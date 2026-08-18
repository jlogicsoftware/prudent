import 'package:zen_ui_navigation/zen_ui_navigation.dart';

/// Prudent's own Polish for `zen_ui_navigation`'s chrome (today just the mobile overflow label),
/// supplied without jZen shipping `pl` (jZen ADR-044). DELETE THIS FILE the day jZen ships `pl`
/// for `zen_ui_navigation`.
class PlNavigationLocalizations extends NavigationLocalizationsEn {
  PlNavigationLocalizations() : super('pl');

  @override
  String get more => 'Więcej';
}
