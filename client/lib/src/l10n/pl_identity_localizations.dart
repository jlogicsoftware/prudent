import 'package:zen_ui_identity/zen_ui_identity.dart';

/// Prudent's own Polish for `zen_ui_identity`'s chrome, supplied without jZen shipping `pl`
/// (jZen ADR-044 — `ZenLocales.shipped` is `{en, uk}`, a floor, not a ceiling). Subclassing the
/// exported `IdentityLocalizationsEn` is the documented seam: a new framework string added
/// upstream shows up here as English until translated, rather than silently missing.
///
/// DELETE THIS FILE THE DAY jZen SHIPS `pl` FOR `zen_ui_identity` — at that point
/// `identityLocaleDelegate` alone resolves it correctly and this override is redundant.
class PlIdentityLocalizations extends IdentityLocalizationsEn {
  PlIdentityLocalizations() : super('pl');

  @override
  String get loginTitle => 'Zaloguj się';

  @override
  String get registerTitle => 'Zarejestruj się';

  @override
  String get restorePasswordTitle => 'Zresetuj hasło';

  @override
  String get emailLabel => 'E-mail';

  @override
  String get passwordLabel => 'Hasło';

  @override
  String get confirmPasswordLabel => 'Potwierdź hasło';

  @override
  String get loginButton => 'Zaloguj się';

  @override
  String get registerButton => 'Utwórz konto';

  @override
  String get confirmEmailTitle => 'Sprawdź swoją skrzynkę';

  @override
  String get confirmEmailBody =>
      'Wysłaliśmy link potwierdzający na Twój e-mail. Potwierdź go, a następnie się zaloguj.';

  @override
  String get sendResetLinkButton => 'Wyślij link';

  @override
  String get logoutButton => 'Wyloguj się';

  @override
  String get profileTitle => 'Profil';

  @override
  String get rolesTitle => 'Twoje role';

  @override
  String get rolesLabel => 'Role:';

  @override
  String get profileAvatarLabel => 'Awatar profilu';

  @override
  String get backButtonTooltip => 'Wstecz';

  @override
  String get restorePasswordInfo =>
      'Podaj swój adres e-mail, a wyślemy Ci link do zresetowania hasła.';

  @override
  String get resetLinkSentSuccess => 'Link resetujący wysłany na Twój e-mail';

  @override
  String get alreadyHaveAccount => 'Masz już konto?';

  @override
  String get noRolesAssigned => 'Nie przypisano żadnych ról';

  @override
  String get notAuthenticated => 'Nie jesteś zalogowany';

  @override
  String get unknownError => 'Wystąpił nieznany błąd.';

  @override
  String get validationRequired => 'Wymagane';

  @override
  String get validationEmail => 'Nieprawidłowy adres e-mail';

  @override
  String get validationPasswordMismatch => 'Hasła nie są zgodne';

  @override
  String get errorUnauthorized => 'Nieprawidłowe dane logowania lub brak dostępu.';

  @override
  String get errorNotFound => 'Nie znaleziono żądanego zasobu.';

  @override
  String get errorValidation => 'Walidacja nie powiodła się. Sprawdź wprowadzone dane.';

  @override
  String get errorConflict => 'Wystąpił konflikt (np. użytkownik już istnieje).';

  @override
  String get errorInvalidCredentials => 'Nieprawidłowy e-mail lub hasło.';

  @override
  String get errorEmailNotConfirmed =>
      'Twój e-mail nie został jeszcze potwierdzony. Sprawdź skrzynkę odbiorczą.';

  @override
  String get emailConfirmedBanner => 'Twój e-mail został potwierdzony. Zaloguj się.';

  @override
  String get emailConfirmedSignedInBanner => 'Twój e-mail został potwierdzony. Witamy!';

  @override
  String get linkExpiredBanner =>
      'Ten link wygasł lub został już użyty. Poproś o nowy.';

  @override
  String get setPasswordTitle => 'Wybierz nowe hasło';

  @override
  String get setPasswordInfo => 'Podaj nowe hasło do swojego konta. Pozostaniesz zalogowany.';

  @override
  String get newPasswordLabel => 'Nowe hasło';

  @override
  String get setPasswordButton => 'Zapisz hasło';

  @override
  String get passwordChangedSuccess => 'Twoje hasło zostało zmienione.';
}
