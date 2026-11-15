package prudent.account;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.regex.Pattern;
import prudent.error.PrudentException;

/**
 * The one definition of a normalised bank account number (M6, ADR-090): what the account form
 * stores, and what a statement importer compares it with, so that two spellings of one number
 * become one string and a number is never compared in two different ways.
 *
 * <p>Normal form: whitespace (any Unicode white space, no-break spaces included) removed, ASCII letters upper-cased (nothing else is case-folded), and a leading {@code PL} dropped from a 26-digit
 * number (a Polish number is written with or without the country prefix, and the bank's statement
 * writes it without). What remains must be 10 to 34 letters and digits. The shape is checked, the
 * IBAN checksum is not: the synthetic fixtures use check digits {@code 00}, which no real IBAN has.
 *
 * <p>Nothing here echoes a number in an exception: it is personal data and an error message ends up
 * in a response body and in logs.
 */
public final class AccountNumbers {

  /**
   * Any Unicode white space, not only ASCII: a number pasted from a PDF or a bank page often carries
   * a no-break space (U+00A0) or a narrow one (U+202F), which Java's plain {@code \s} does not match.
   */
  private static final Pattern WHITE_SPACE = Pattern.compile("(?U)\\s+");

  private static final Pattern SHAPE = Pattern.compile("[A-Z0-9]{10,34}");
  private static final Pattern POLISH_WITH_PREFIX = Pattern.compile("PL[0-9]{26}");

  private AccountNumbers() {}

  /**
   * The normal form of {@code raw}, or {@code null} when it is {@code null} or blank (no number).
   *
   * @throws PrudentException (400) when something is there and is not a number's shape
   */
  public static String normalize(String raw) {
    String canonical = canonical(raw);
    if (canonical == null) {
      return null;
    }
    String normalised = shaped(canonical);
    if (normalised == null) {
      throw PrudentException.invalid(
          "The account number must be 10 to 34 letters and digits; spaces are ignored.");
    }
    return normalised;
  }

  /**
   * As {@link #normalize} but answers {@code null} for text that is not a number's shape (and for
   * none at all), for a caller that rejects with its own rule code.
   */
  public static String normalizeOrNull(String raw) {
    String canonical = canonical(raw);
    return canonical == null ? null : shaped(canonical);
  }

  /**
   * The identity token of an account identifier: SHA-256 of {@link #canonical}, lower-case hex (64
   * characters). The one definition of the token, so that a statement's number and a stored one
   * compare equal exactly when their canonical forms are equal. The shape is not required here (a
   * test importer identifies an account by its name); {@link #normalize} is what enforces it.
   *
   * @throws IllegalArgumentException when nothing is left after normalising (never carries it)
   */
  public static String identityOf(String raw) {
    String canonical = canonical(raw);
    if (canonical == null) {
      throw new IllegalArgumentException("an account number is required to derive its identity");
    }
    try {
      byte[] digest =
          MessageDigest.getInstance("SHA-256").digest(canonical.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(digest);
    } catch (NoSuchAlgorithmException impossible) {
      throw new IllegalStateException("SHA-256 is required of every Java runtime", impossible);
    }
  }

  /**
   * The canonical form without the shape check: Unicode white space removed, ASCII upper-cased ({@link #asciiUpperCase}), a leading {@code PL} dropped from a 26-digit number; {@code null} when nothing is
   * left. The single place a number is normalised.
   */
  public static String canonical(String raw) {
    String compact = compact(raw);
    if (compact == null) {
      return null;
    }
    return POLISH_WITH_PREFIX.matcher(compact).matches() ? compact.substring(2) : compact;
  }

  /** White space removed and upper-cased, or {@code null} when nothing is left. */
  private static String compact(String raw) {
    if (raw == null) {
      return null;
    }
    String compact = asciiUpperCase(WHITE_SPACE.matcher(raw).replaceAll(""));
    return compact.isEmpty() ? null : compact;
  }

  /**
   * Upper-cases the letters {@code a} to {@code z} and nothing else. {@link String#toUpperCase}
   * would also fold characters outside the shape into it ({@code ß} becomes {@code SS}, a dotless
   * {@code ı} becomes {@code I}, a long {@code ſ} becomes {@code S}), so two different typed strings
   * could be stored as one number; here such a character stays what it is and the shape check
   * refuses it.
   */
  private static String asciiUpperCase(String text) {
    StringBuilder upper = new StringBuilder(text.length());
    for (int i = 0; i < text.length(); i++) {
      char c = text.charAt(i);
      upper.append(c >= 'a' && c <= 'z' ? (char) (c - 'a' + 'A') : c);
    }
    return upper.toString();
  }

  private static String shaped(String canonical) {
    return SHAPE.matcher(canonical).matches() ? canonical : null;
  }
}
