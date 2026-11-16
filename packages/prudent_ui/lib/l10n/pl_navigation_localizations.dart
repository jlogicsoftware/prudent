import 'package:zen_ui_navigation/zen_ui_navigation.dart';

/// Prudent's own Polish for `zen_ui_navigation`'s chrome (the mobile overflow label and the sidebar's "2 of 5" position hint),
/// supplied without jZen shipping `pl` (jZen ADR-044). DELETE THIS FILE the day jZen ships `pl`
/// for `zen_ui_navigation`.
class PlNavigationLocalizations extends NavigationLocalizationsEn {
  PlNavigationLocalizations() : super('pl');

  @override
  String get more => 'Więcej';

  @override
  String position(int index, int count) => '$index z $count';
}
