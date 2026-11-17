import 'package:intl/intl.dart' as intl;
import 'package:zen_ui_store/zen_ui_store.dart';

/// Polish for `zen_ui_store`'s conflict, sync-status and pairing screens, which jZen ships in
/// English and Ukrainian only (jZen ADR-044). Prudent supports Polish (its own decision), so it
/// supplies the wording, as the server-connected app does for identity and navigation.
class PlStoreLocalizations extends StoreLocalizations {
  PlStoreLocalizations() : super('pl');

  String _plural(
    int count, {
    required String one,
    required String few,
    required String many,
  }) => intl.Intl.pluralLogic(
    count,
    locale: 'pl',
    one: one,
    few: few,
    many: many,
    other: many,
  );

  @override
  String get conflictsTitle => 'Zmienione na dwóch urządzeniach';
  @override
  String get conflictsIntro =>
      'Te pozycje zmieniono inaczej na Twoich urządzeniach. Nic nie zostało odrzucone: wybierz, '
      'którą wersję zachować.';
  @override
  String get noConflicts => 'Wszystko jest zsynchronizowane.';
  @override
  String bannerText(int count) => _plural(
    count,
    one: '1 pozycję zmieniono na dwóch urządzeniach i czeka na Twój wybór.',
    few:
        '$count pozycje zmieniono na dwóch urządzeniach i czekają na Twój wybór.',
    many:
        '$count pozycji zmieniono na dwóch urządzeniach i czeka na Twój wybór.',
  );
  @override
  String get reviewButton => 'Przejrzyj';
  @override
  String get resolveTitle => 'Wybierz wersję';
  @override
  String resolveIntro(String title) =>
      '$title zmieniono na więcej niż jednym urządzeniu. Zachowaj jedną wersję; pozostałe zostaną '
      'zastąpione na każdym urządzeniu.';
  @override
  String sideHeading(String device, String time) => '$device, $time';
  @override
  String get deletedHere => 'Usunięto na tym urządzeniu';
  @override
  String get notSet => '(puste)';
  @override
  String get keepThisVersion => 'Zachowaj tę wersję';
  @override
  String get keepDeleted => 'Pozostaw usunięte';
  @override
  String get resolveFailed =>
      'Nie udało się zapisać Twojego wyboru. Spróbuj ponownie.';
  @override
  String bulkRowTitle(int count, String first, String second) =>
      'Rozstrzygnij wszystkie $count zmienione na $first i $second';
  @override
  String get bulkRowSubtitle =>
      'Zachowaj wersję jednego urządzenia dla każdej z nich';
  @override
  String get bulkTitle => 'Rozstrzygnij wiele naraz';
  @override
  String bulkIntro(int count, String first, String second) =>
      'Liczba pozycji zmienionych inaczej na $first i $second: $count. Wybierz urządzenie, którego '
      'wersję zachować dla wszystkich. Druga wersja każdej zostanie zastąpiona na każdym urządzeniu.';
  @override
  String bulkKeepThisDevice(int count, String device) =>
      'Zachowaj wersję tego urządzenia ($device) dla wszystkich ($count)';
  @override
  String bulkKeepDevice(int count, String device) =>
      'Zachowaj wersję urządzenia $device dla wszystkich ($count)';
  @override
  String bulkIncludedHeading(int count) => 'Rozstrzygane razem ($count)';
  @override
  String bulkLeftHeading(int count) => 'Pozostawione dla Ciebie ($count)';
  @override
  String get bulkLeftIntro =>
      'Te dotyczą też usunięcia albo trzeciego urządzenia, więc ten wybór ich nie obejmuje. '
      'Rozstrzygnij każdą osobno.';
  @override
  String bulkResult(int done, int total) =>
      'Rozstrzygnięto $done z $total. Pozostałe zmieniły się w międzyczasie albo nie dały się '
      'zapisać i nadal czekają na Twój wybór.';
  @override
  String get bulkBack => 'Wróć do listy';
  @override
  String get deletedTitle => 'Usunięta pozycja';
  @override
  String get syncNoAccount =>
      'Brak synchronizacji: to urządzenie nie jest zalogowane do iCloud. Twoje dane są tu '
      'bezpieczne; zaloguj się w Ustawieniach, aby je synchronizować.';
  @override
  String get syncKeychainUnavailable =>
      'Brak synchronizacji: pęk kluczy iCloud jest wyłączony, więc zaszyfrowanych danych nie można '
      'tu odczytać. Włącz go w Ustawienia → iCloud → Hasła i pęk kluczy.';
  @override
  String get syncAccountChanged =>
      'Synchronizacja zatrzymana: to urządzenie jest teraz zalogowane do innego konta iCloud. '
      'Nic do niego nie wysłano.';
  @override
  String get syncCloudDataDeleted =>
      'Synchronizacja zatrzymana: dane w iCloud zostały usunięte. Kopia na tym urządzeniu jest '
      'nienaruszona.';
  @override
  String get syncQuotaExceeded =>
      'Brak synchronizacji: Twój magazyn iCloud jest pełny.';
  @override
  String get syncUnreadableRecords =>
      'Niektórych zmian z innego urządzenia nie można tu odczytać. Zaktualizuj aplikację na tym '
      'urządzeniu.';
  @override
  String get syncOther =>
      'Synchronizacja teraz nie działa. Twoje dane są bezpieczne na tym urządzeniu.';
  @override
  String get syncNoFolder =>
      'Brak synchronizacji: nie wybrano jeszcze folderu synchronizacji. Twoje dane są tu '
      'bezpieczne; wybierz folder, aby je synchronizować.';
  @override
  String get syncFolderUnreachable =>
      'Brak synchronizacji: folder synchronizacji jest niedostępny. Mógł zostać przeniesiony, '
      'usunięty albo jego dysk odłączony.';
  @override
  String get syncAccessRevoked =>
      'Brak synchronizacji: aplikacja nie ma już dostępu do folderu synchronizacji. Wybierz folder '
      'ponownie, aby na to zezwolić.';
  @override
  String get syncNotPaired =>
      'Brak synchronizacji: to urządzenie nie jest jeszcze połączone. Połącz je z urządzeniem, '
      'którego już używasz.';
  @override
  String get syncNewerAppVersion =>
      'Niektóre zmiany z innego urządzenia zrobiono nowszą wersją aplikacji. Zaktualizuj '
      'aplikację na tym urządzeniu.';
  @override
  String get syncErasedEverywhere =>
      'Wszystkie Twoje dane zostały wymazane na każdym urządzeniu. Nie ma już czego synchronizować.';
  @override
  String get syncKeyReplaced =>
      'Brak synchronizacji: usunięto urządzenie i wymieniono klucz synchronizacji. Połącz to '
      'urządzenie ponownie z urządzeniem, które ma nowy klucz.';
  @override
  String get addDeviceTitle => 'Dodaj urządzenie';
  @override
  String get addDeviceIntro =>
      'Na nowym urządzeniu wybierz Dołącz, a potem zeskanuj ten kod albo go wpisz. Kod jest ważny '
      '5 minut. Każdy, kto go zobaczy, może odczytać Twoje dane, więc nie pokazuj ekranu innym.';
  @override
  String get showCodeButton => 'Pokaż kod';
  @override
  String get cancelButton => 'Anuluj';
  @override
  String get qrCodeLabel =>
      'Kod QR z kodem łączenia, do zeskanowania przez nowe urządzenie';
  @override
  String get pairingCodeLabel => 'Kod łączenia';
  @override
  String codeValidFor(String time) => 'Ważny przez $time';
  @override
  String get codeExpired => 'Ten kod wygasł. Nie jest już wyświetlany.';
  @override
  String get codeHidden => 'Kod został ukryty, bo aplikacja opuściła ekran.';
  @override
  String get showNewCodeButton => 'Pokaż nowy kod';
  @override
  String get joinTitle => 'Dołącz';
  @override
  String get joinIntro =>
      'Na urządzeniu, które ma już Twoje dane, wybierz Dodaj urządzenie. Potem zeskanuj kod, który '
      'pokazuje, albo wpisz go tutaj.';
  @override
  String get joinCodeHint => 'Siedem znaków, potem myślnik, jedenaście razy';
  @override
  String get joinButton => 'Dołącz';
  @override
  String get scanButton => 'Skanuj aparatem';
  @override
  String get typeInsteadButton => 'Wpisz kod zamiast tego';
  @override
  String get joinWrongLength => 'To nie jest cały kod. Ma 11 grup po 7 znaków.';
  @override
  String get joinBadCharacter =>
      'Kod ma tylko cyfry i litery. Sprawdź, co wpisano.';
  @override
  String joinMistyped(int group) =>
      'Grupa $group zawiera błąd. Porównaj ją z drugim urządzeniem.';
  @override
  String get joinScrambled =>
      'Grupy są w złej kolejności. Wpisz je tak, jak są pokazane.';
  @override
  String get joinUnsupported =>
      'Ten kod pochodzi z nowszej wersji aplikacji. Zaktualizuj to urządzenie i spróbuj ponownie.';
  @override
  String get joinExpired => 'Ten kod wygasł. Pokaż nowy na drugim urządzeniu.';
  @override
  String joinFailed(String reason) => 'Dołączenie nie powiodło się: $reason';
  @override
  String bannerAttention(int count) => _plural(
    count,
    one: '1 pozycja czeka na Twój wybór.',
    few: '$count pozycje czekają na Twój wybór.',
    many: '$count pozycji czeka na Twój wybór.',
  );
  @override
  String get attentionIntro =>
      'Te czekają na Twój wybór. Nic nie zostało odrzucone ani zmienione bez Ciebie.';
  @override
  String get issueTitle => 'Czeka na Twój wybór';
  @override
  String issueFailed(String reason) => 'Nie udało się tego zrobić: $reason';
}
