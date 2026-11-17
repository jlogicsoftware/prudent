import 'package:zen_ui_lock/zen_ui_lock.dart';

/// Polish for `zen_ui_lock`'s screens, which jZen ships in English and Ukrainian only (jZen
/// ADR-044): Prudent supports Polish (its own decision), so it supplies the wording, exactly as the
/// server-connected app does for the identity and navigation packages.
class PlLockLocalizations extends LockLocalizations {
  PlLockLocalizations() : super('pl');

  @override
  String get unlockTitle => 'Wpisz kod PIN';
  @override
  String get pinLabel => 'PIN';
  @override
  String get unlockButton => 'Odblokuj';
  @override
  String get forgotPinButton => 'Nie pamiętasz kodu PIN?';
  @override
  String get forgotPinReason =>
      'Potwierdź, że to Ty, aby zresetować kod PIN aplikacji';
  @override
  String get ownerNotConfirmed =>
      'Nie udało się potwierdzić, że to Ty. Kod PIN nie został zresetowany.';
  @override
  String get wrongPin => 'Nieprawidłowy kod PIN';
  @override
  String lockedOut(int seconds) =>
      'Zbyt wiele błędnych kodów PIN. Spróbuj ponownie za $seconds s.';
  @override
  String get pinFormat => 'Użyj od 4 do 8 cyfr';
  @override
  String get setPinTitle => 'Ustaw kod PIN';
  @override
  String get changePinTitle => 'Zmień kod PIN';
  @override
  String get turnOffPinTitle => 'Wyłącz kod PIN';
  @override
  String get currentPinLabel => 'Obecny kod PIN';
  @override
  String get newPinLabel => 'Nowy kod PIN';
  @override
  String get repeatPinLabel => 'Powtórz kod PIN';
  @override
  String get pinsDoNotMatch => 'Kody PIN się nie zgadzają';
  @override
  String get saveButton => 'Zapisz';
  @override
  String get turnOffButton => 'Wyłącz';
  @override
  String get lockWithPin => 'Blokuj kodem PIN';
  @override
  String get lockWithPinHint => 'Pytaj o kod PIN przy otwieraniu aplikacji';
  @override
  String get lockError =>
      'Nie udało się zapisać blokady aplikacji. Spróbuj ponownie.';
  @override
  String get eraseTitle => 'Wymazać kopię na tym urządzeniu?';
  @override
  String get eraseExplanation =>
      'To urządzenie nie może potwierdzić, że to Ty, więc kodu PIN nie da się zresetować wprost. '
      'Wymazanie usuwa dane aplikacji z tego urządzenia i wyłącza kod PIN. Jeśli Twoje inne '
      'urządzenia są zsynchronizowane, odeślą dane; to, co nie zostało jeszcze zsynchronizowane, '
      'przepadnie.';
  @override
  String get eraseButton => 'Wymaż i zresetuj kod PIN';
  @override
  String get cancelButton => 'Anuluj';
  @override
  String get eraseFailed =>
      'Nie udało się wymazać kopii na tym urządzeniu. Kod PIN nie został zresetowany.';
  @override
  String get recoveryUnknown =>
      'Nie udało się sprawdzić, czy to urządzenie może zresetować zapomniany kod PIN.';
  @override
  String get retryButton => 'Spróbuj ponownie';
}
