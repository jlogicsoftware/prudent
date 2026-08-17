package prudent.server;

import java.util.Currency;
import java.util.Locale;

/**
 * ISO-4217 currency codes — validation and normalisation, in one place.
 *
 * <p><strong>The JDK is the authority, not a list in this repository.</strong>
 * {@link Currency#getInstance(String)} is backed by the JDK's own ISO-4217 table and refuses
 * anything not in it. A hand-maintained set would be a second copy of a standard that changes
 * without asking us, and its failure mode is rejecting a currency that legitimately exists.
 *
 * <p><strong>This is why {@code quarkus.locales} is set.</strong> The native image bakes JDK locale
 * and currency data at build time, so a native binary built without it carries a narrower table
 * than the JVM this validates against — the same code would then reject a currency in production
 * that it accepts in every test. See {@code application.properties}.
 */
public final class Currencies {

  private Currencies() {}

  /**
   * The canonical form of a currency code: trimmed and upper-cased.
   *
   * <p>Normalising before storing is what stops "pln" and "PLN" becoming two balances of one
   * account. Upper-casing is done in {@link Locale#ROOT} rather than the default locale, because
   * the Turkish locale maps {@code i} to {@code İ} and would corrupt any code containing one.
   *
   * @param code a candidate code, possibly {@code null}
   * @return the normalised code, or {@code null} if {@code code} was {@code null}
   */
  public static String normalize(String code) {
    return code == null ? null : code.trim().toUpperCase(Locale.ROOT);
  }

  /**
   * Whether a code names a real ISO-4217 currency.
   *
   * <p>Normalises first, so a caller does not have to remember to. Blank and {@code null} are
   * refused rather than treated as "unset" — the callers that permit an empty value handle it
   * before reaching here, so that the two meanings never depend on which method was called.
   *
   * @param code the candidate, in any case, possibly {@code null}
   * @return {@code true} only for a code the JDK's ISO-4217 table knows
   */
  public static boolean isValid(String code) {
    String normalized = normalize(code);
    if (normalized == null || normalized.length() != 3) {
      return false;
    }
    try {
      Currency.getInstance(normalized);
      return true;
    } catch (IllegalArgumentException notACurrency) {
      // The JDK signals "no such currency" by throwing. That is the answer to the question this
      // method asks, so it is converted to false here — and ONLY here, where the question is
      // literally "is this valid". Nothing else in this server swallows it.
      return false;
    }
  }
}
