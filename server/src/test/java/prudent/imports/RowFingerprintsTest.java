package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.imports.RowFingerprints.Fields;

/**
 * The fingerprint and occurrence scheme on its own (M6, jlogicsoftware/prudent#75, ADR-091): pure,
 * so every property the duplicate stage relies on is checked here without a database. Every
 * statement text is synthetic.
 */
class RowFingerprintsTest {

  private static final UUID ACCOUNT = UUID.fromString("00000000-0000-0000-0000-00000000000a");
  private static final UUID OTHER_ACCOUNT = UUID.fromString("00000000-0000-0000-0000-00000000000b");
  private static final LocalDate DAY = LocalDate.of(2026, 3, 5);
  private static final String CARD =
      "DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 7.10 PLN KOMUNIKACJA TESTOWA";

  private static Fields row(LocalDate day, long amount, String description) {
    return new Fields(day, amount, description, null, null);
  }

  private static String fp(Fields fields) {
    return RowFingerprints.fingerprint(ACCOUNT, "erste-pl-csv", "PLN", fields);
  }

  @Test
  void aFingerprintIsAVersionedDigestAndNeverTheText() {
    String fingerprint = fp(row(DAY, -710, CARD));

    assertTrue(fingerprint.matches("v1:[0-9a-f]{64}"), fingerprint);
    assertTrue(fingerprint.matches(RowFingerprints.KEY_SHAPE));
    assertFalse(fingerprint.toUpperCase().contains("KOMUNIKACJA"));
  }

  @Test
  void theSameRowAlwaysGivesTheSameFingerprint() {
    assertEquals(fp(row(DAY, -710, CARD)), fp(row(DAY, -710, CARD)));
  }

  @Test
  void everyFieldTheSchemeReadsChangesTheFingerprint() {
    String base = fp(row(DAY, -710, CARD));
    Set<String> all = new HashSet<>(List.of(base));

    all.add(fp(row(DAY.plusDays(1), -710, CARD)));
    all.add(fp(row(DAY, -711, CARD)));
    all.add(fp(row(DAY, 710, CARD)));
    all.add(fp(row(DAY, -710, CARD + " X")));
    all.add(fp(new Fields(DAY, -710, CARD, "COUNTERPARTY", null)));
    all.add(fp(new Fields(DAY, -710, CARD, null, "00000000000000000000000010")));
    all.add(RowFingerprints.fingerprint(OTHER_ACCOUNT, "erste-pl-csv", "PLN", row(DAY, -710, CARD)));
    all.add(RowFingerprints.fingerprint(ACCOUNT, "other-format", "PLN", row(DAY, -710, CARD)));
    all.add(RowFingerprints.fingerprint(ACCOUNT, "erste-pl-csv", "EUR", row(DAY, -710, CARD)));

    assertEquals(10, all.size(), "each of nine variations must differ from the base and each other");
  }

  @Test
  void fieldBoundariesCannotBeShifted() {
    // Text moving from one field to the next must not produce the same input.
    assertNotEquals(
        fp(new Fields(DAY, -1, "AB", "C", null)), fp(new Fields(DAY, -1, "A", "BC", null)));
    assertNotEquals(
        fp(new Fields(DAY, -1, "AB", null, null)), fp(new Fields(DAY, -1, "A", "B", null)));
  }

  @Test
  void whiteSpaceCaseAndUnicodeFormDoNotChangeTheFingerprint() {
    String base = fp(row(DAY, -710, "Zakup BLIK Sklep Testowy ref:00000000001"));

    assertEquals(base, fp(row(DAY, -710, "  zakup  BLIK\tSKLEP testowy ref:00000000001 ")));
    // "Ł" and "ś" in composed and decomposed Unicode forms are the same text.
    assertEquals(
        fp(row(DAY, -1, "PŁATNOŚĆ")),
        fp(row(DAY, -1, "PŁATNOŚĆ".replace("Ś", "Ś").replace("Ć", "Ć"))));
    assertEquals(fp(new Fields(DAY, -1, "X", null, null)), fp(new Fields(DAY, -1, "X", "", "")));
  }

  @Test
  void punctuationAndLettersAreNotNormalisedAway() {
    // Folding these would also merge two genuinely different operations.
    assertNotEquals(fp(row(DAY, -1, "SKLEP A.")), fp(row(DAY, -1, "SKLEP A")));
    assertNotEquals(fp(row(DAY, -1, "ŁÓDŹ")), fp(row(DAY, -1, "LODZ")));
  }

  @Test
  void identicalRowsInOneStatementGetOccurrencesOneToN() {
    String a = fp(row(DAY, -710, CARD));
    String b = fp(row(DAY, -500, "OTHER"));

    List<RowKey> keys = RowFingerprints.keys(List.of(a, b, a, a));

    assertEquals(
        List.of(new RowKey(a, 1), new RowKey(b, 1), new RowKey(a, 2), new RowKey(a, 3)), keys);
  }

  @Test
  void anOverlapThatCutsThroughAGroupOfIdenticalRowsYieldsExactlyTheNewOne() {
    String a = fp(row(DAY, -710, CARD));
    String earlier = fp(row(DAY.minusDays(3), -100, "EARLIER"));

    // The older export ends mid-day with two of the three identical rows.
    Set<RowKey> imported = new HashSet<>(RowFingerprints.keys(List.of(a, a, earlier)));
    // The newer export has all three, in another position, with new rows above.
    String newer = fp(row(DAY.plusDays(2), -42, "NEWER"));
    List<String> second = List.of(newer, a, a, a, earlier);
    List<RowKey> keys = RowFingerprints.keys(second);

    List<RowKey> fresh = new ArrayList<>();
    for (RowKey key : keys) {
      if (!imported.contains(key)) {
        fresh.add(key);
      }
    }
    assertEquals(List.of(new RowKey(newer, 1), new RowKey(a, 3)), fresh);
  }

  @Test
  void theOrderOfRowsDoesNotChangeWhichKeysExist() {
    String a = fp(row(DAY, -1, "A"));
    String b = fp(row(DAY, -2, "B"));

    assertEquals(
        new HashSet<>(RowFingerprints.keys(List.of(a, b, a, b, a))),
        new HashSet<>(RowFingerprints.keys(List.of(a, a, a, b, b))));
  }

  @Test
  void aKeyBuiltFromAStableIdentifierIsOccurrenceOneAndAccountScoped() {
    RowKey key = RowFingerprints.stableIdKey(ACCOUNT, "fmt", "17");

    assertEquals(1, key.occurrence());
    assertTrue(key.fingerprint().startsWith("e1:"));
    assertEquals(key, RowFingerprints.stableIdKey(ACCOUNT, "fmt", " 17 "));
    assertNotEquals(key, RowFingerprints.stableIdKey(OTHER_ACCOUNT, "fmt", "17"));
    assertNotEquals(key, RowFingerprints.stableIdKey(ACCOUNT, "fmt", "18"));
    assertThrows(IllegalArgumentException.class, () -> RowFingerprints.stableIdKey(ACCOUNT, "fmt", " "));
  }

  @Test
  void aKeyRefusesAMalformedFingerprintOrOccurrence() {
    String good = fp(row(DAY, -1, "X"));
    assertThrows(IllegalArgumentException.class, () -> new RowKey("not a digest", 1));
    assertThrows(IllegalArgumentException.class, () -> new RowKey(null, 1));
    assertThrows(IllegalArgumentException.class, () -> new RowKey(good, 0));
  }

  @Test
  void normaliseIsIdempotentIncludingWhereUpperCasingRecomposes() {
    // Greek with iota subscript (U+1FB3) and sharp s change shape when upper-cased.
    for (String text :
        List.of("\u1FB3 \u03B1\u0345", "stra\u00DFe", "e\u0301cole", " a\u00A0\u00A0b ", "\u0130stanbul")) {
      String once = RowFingerprints.normalise(text);
      assertEquals(once, RowFingerprints.normalise(once), text);
    }
  }
}
