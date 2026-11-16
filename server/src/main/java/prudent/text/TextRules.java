package prudent.text;

import java.util.UUID;

/**
 * The two text rules a person can see in Prudent's lists, stated so that a second implementation
 * (Prudent Local's Dart code) reproduces them exactly (ADR-105): how a search term is cleaned and
 * matched, and how names are ordered.
 *
 * <p>Neither rule asks the database. A database folds case and orders text by whatever locale it
 * was created with, which no migration pins and a Dart program cannot reproduce; so the server
 * loads the rows its other filters selected and applies these rules in Java. Both rules are
 * per-code-point and context-free on purpose: no locale, no normalisation, no final-sigma rule.
 *
 * <p>The expected behaviour is in {@code src/test/resources/text-rules/*.json}, which {@code
 * TextRulesTest} runs and Prudent Local's parity suite reads.
 */
public final class TextRules {

  private TextRules() {}

  /**
   * Fold one code point: Unicode's <em>simple</em> lower-case mapping, one code point to one code
   * point, whatever the language. {@code İ} (U+0130) becomes {@code i}, {@code ß} is unchanged, and
   * {@code Σ} is always {@code σ}. A code point with no lower-case form is itself.
   */
  public static int foldCodePoint(int codePoint) {
    return Character.toLowerCase(codePoint);
  }

  /** {@link #foldCodePoint} over every code point of {@code text}. */
  public static String fold(String text) {
    StringBuilder out = new StringBuilder(text.length());
    text.codePoints().forEach(cp -> out.appendCodePoint(foldCodePoint(cp)));
    return out.toString();
  }

  /**
   * The folded search term, or {@code null} when the search is to be ignored. A {@code null} or
   * blank search ({@link String#isBlank}: Unicode white space, which does <em>not</em> include
   * U+00A0, U+2007 or U+202F) is ignored; otherwise the term is {@link String#trim}med (every
   * leading and trailing code point at or below U+0020) and folded. {@code %}, {@code _} and
   * {@code \} are ordinary characters.
   */
  public static String searchTerm(String search) {
    if (search == null || search.isBlank()) {
      return null;
    }
    return fold(search.trim());
  }

  /**
   * Whether any of {@code fields} contains {@code term} (from {@link #searchTerm}) after folding.
   * A {@code null} field never matches.
   */
  public static boolean matchesAny(String term, String... fields) {
    for (String field : fields) {
      if (field != null && fold(field).contains(term)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Compare two names the way every list of accounts, categories and free-money accounts is
   * ordered: by {@link #collationKey}, then by the names' code points exactly as written (so
   * {@code A} comes before {@code a}), then by id as lower-case text — which is also the order
   * Postgres gives a UUID, byte by byte.
   */
  public static int compareNames(String a, UUID idA, String b, UUID idB) {
    int[] keyA = collationKey(a);
    int[] keyB = collationKey(b);
    int n = Math.min(keyA.length, keyB.length);
    for (int i = 0; i < n; i++) {
      if (keyA[i] != keyB[i]) {
        return Integer.compare(keyA[i], keyB[i]);
      }
    }
    if (keyA.length != keyB.length) {
      return Integer.compare(keyA.length, keyB.length);
    }
    int[] rawA = a.codePoints().toArray();
    int[] rawB = b.codePoints().toArray();
    n = Math.min(rawA.length, rawB.length);
    for (int i = 0; i < n; i++) {
      if (rawA[i] != rawB[i]) {
        return Integer.compare(rawA[i], rawB[i]);
      }
    }
    if (rawA.length != rawB.length) {
      return Integer.compare(rawA.length, rawB.length);
    }
    return idA.toString().compareTo(idB.toString());
  }

  /**
   * The primary weight of every folded code point of {@code name}. A code point weighs four times
   * its own value, so code point order is the baseline; the letters Prudent's languages add to
   * their alphabets take the slots between their base letter and the next one, which is where a
   * Polish or Ukrainian reader looks for them:
   *
   * <ul>
   *   <li>Polish: a ą, c ć, e ę, l ł, n ń, o ó, s ś, z ź ż — each right after its base letter.
   *   <li>Ukrainian: г ґ, е є, и і ї (then й, which already follows и in Unicode).
   * </ul>
   *
   * <p>Every other code point keeps its Unicode position: digits and punctuation before letters,
   * Latin before Cyrillic, an accented French or German letter after {@code z}. Text is not
   * normalised, so a letter typed as a base plus a combining mark orders by its parts.
   */
  static int[] collationKey(String name) {
    return fold(name).codePoints().map(TextRules::weight).toArray();
  }

  private static int weight(int cp) {
    return switch (cp) {
      case 0x0105 -> 'a' * 4 + 1; // ą
      case 0x0107 -> 'c' * 4 + 1; // ć
      case 0x0119 -> 'e' * 4 + 1; // ę
      case 0x0142 -> 'l' * 4 + 1; // ł
      case 0x0144 -> 'n' * 4 + 1; // ń
      case 0x00F3 -> 'o' * 4 + 1; // ó
      case 0x015B -> 's' * 4 + 1; // ś
      case 0x017A -> 'z' * 4 + 1; // ź
      case 0x017C -> 'z' * 4 + 2; // ż
      case 0x0491 -> 0x0433 * 4 + 1; // ґ after г
      case 0x0454 -> 0x0435 * 4 + 1; // є after е
      case 0x0456 -> 0x0438 * 4 + 1; // і after и
      case 0x0457 -> 0x0438 * 4 + 2; // ї after і
      default -> cp * 4;
    };
  }
}
