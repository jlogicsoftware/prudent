package prudent.imports;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.Normalizer;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * How a statement row is recognised the next time it is imported (M6,
 * jlogicsoftware/prudent#75, ADR-091). Pure: no database, no CDI, no clock, so the scheme can be
 * tested exhaustively and cannot drift with its surroundings.
 *
 * <h2>The scheme ({@value #FINGERPRINT_PREFIX})</h2>
 *
 * <p>The fingerprint is SHA-256 over, in order: a fixed scheme tag, the destination account's id,
 * the format id, the statement's currency, the transaction date, the signed amount in minor units
 * and the normalised description, counterparty and counterparty account. Every text field goes
 * through {@link #normalise}; each is written with its length so that no two different field
 * lists can produce the same bytes.
 *
 * <p><strong>Deliberately left out</strong>, because it can differ for the same operation between
 * two exports or says nothing about the operation:
 *
 * <ul>
 *   <li>the bank's sequence number and the row's position — it is a rank counted from the newest
 *       row of one export (docs/erste-csv-contract.md), so it moves when a later export adds newer
 *       rows;
 *   <li>the booking date — the contract says it is not monotonic, can be later than the export
 *       date, and whether such a row can still change is unknown;
 *   <li>the balance column — it does not chain, and is not even read by the importer.
 * </ul>
 *
 * <p>The BLIK reference stays inside the description, so two BLIK payments to one merchant for the
 * same amount on one day differ by it, which is stronger than the occurrence number below.
 *
 * <h2>Occurrence numbers</h2>
 *
 * <p>A real statement legitimately holds identical-looking rows (two tickets, one merchant, one
 * day). They share a fingerprint, so a fingerprint alone would collapse them. {@link #keys} gives
 * the n-th row of one statement with a given fingerprint the occurrence n. Rows with one
 * fingerprint are interchangeable by definition, so which of them is called 1 does not matter, only
 * how many there are: this is what makes an overlap that cuts through such a group work. The older
 * export holds two of three identical rows (keys 1 and 2), the newer holds all three (1, 2, 3), and
 * only 3 is new.
 *
 * <h2>Why a digest, and what it is not</h2>
 *
 * <p>The key goes into a ledger column that nothing displays, so it should not be statement text
 * again; a digest keeps the comparison and drops the text. It is <strong>not secret</strong>: the
 * input is short and low-entropy, so anyone who can read the table can test guesses (the account id
 * only stops one table of precomputed digests from serving every account). It is stored as personal
 * data, never sent over the wire and never logged.
 *
 * <h2>The switch for a stable bank identifier</h2>
 *
 * <p>If a format ever shows that its own entry identifier survives overlapping exports, it says so
 * by returning true from {@link StatementImporter#stableExternalId()}; {@link #stableIdKey} then
 * keys each row by that identifier, with occurrence 1 (an identifier is unique by construction, so
 * there is no group to count). No format does today.
 */
public final class RowFingerprints {

  /** The scheme prefix of a content fingerprint. A change to the scheme is a new prefix. */
  public static final String FINGERPRINT_PREFIX = "v1";

  /** The scheme prefix of a key built from a bank identifier believed stable. */
  public static final String STABLE_ID_PREFIX = "e1";

  /** The shape of every key, as the database's CHECK constraints also require. */
  public static final String KEY_SHAPE = "[a-z][0-9]+:[0-9a-f]{64}";

  private static final Pattern WHITE_SPACE = Pattern.compile("(?U)\\s+");

  /**
   * The fields of a row the fingerprint reads, as the importer normalised them.
   *
   * @param transactionDate the day of the operation
   * @param amountMinor signed minor units
   * @param description the bank's description; may be {@code null}
   * @param counterparty may be {@code null}
   * @param counterpartyAccount may be {@code null}
   */
  public record Fields(
      LocalDate transactionDate,
      long amountMinor,
      String description,
      String counterparty,
      String counterpartyAccount) {}

  private RowFingerprints() {}

  /**
   * The fingerprint of one row in one destination account.
   *
   * @param accountId the destination account
   * @param formatId the importer's format id
   * @param currency the statement's currency
   */
  public static String fingerprint(UUID accountId, String formatId, String currency, Fields row) {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    put(out, "prudent.import.row." + FINGERPRINT_PREFIX);
    put(out, accountId.toString());
    put(out, formatId);
    put(out, currency);
    put(out, row.transactionDate().toString());
    put(out, Long.toString(row.amountMinor()));
    put(out, normalise(row.description()));
    put(out, normalise(row.counterparty()));
    put(out, normalise(row.counterpartyAccount()));
    return FINGERPRINT_PREFIX + ":" + sha256(out.toByteArray());
  }

  /** The key of a row identified by a bank identifier trusted to be stable; occurrence 1. */
  public static RowKey stableIdKey(UUID accountId, String formatId, String externalId) {
    if (externalId == null || externalId.isBlank()) {
      throw new IllegalArgumentException("A stable identifier is required to key a row by it.");
    }
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    put(out, "prudent.import.id." + STABLE_ID_PREFIX);
    put(out, accountId.toString());
    put(out, formatId);
    put(out, externalId.strip());
    return new RowKey(STABLE_ID_PREFIX + ":" + sha256(out.toByteArray()), 1);
  }

  /**
   * The keys of a statement's rows, in the order given: the n-th row with a fingerprint gets
   * occurrence n.
   *
   * @param fingerprints one per row, from {@link #fingerprint}
   */
  public static List<RowKey> keys(List<String> fingerprints) {
    Map<String, Integer> seen = new HashMap<>();
    List<RowKey> keys = new ArrayList<>(fingerprints.size());
    for (String fingerprint : fingerprints) {
      keys.add(new RowKey(fingerprint, seen.merge(fingerprint, 1, Integer::sum)));
    }
    return keys;
  }

  /**
   * One normal form for the text a bank writes: Unicode NFC, every run of white space (a no-break
   * space included) one space, trimmed, upper-cased in the root locale; {@code null} is empty.
   * Meant to survive an export that spaces or cases the same words differently, and nothing more:
   * it does not drop punctuation, transliterate letters or reorder words, because each of those
   * would also merge two genuinely different operations.
   */
  public static String normalise(String text) {
    if (text == null) {
      return "";
    }
    String composed = Normalizer.normalize(text, Normalizer.Form.NFC);
    String upper = WHITE_SPACE.matcher(composed).replaceAll(" ").strip().toUpperCase(Locale.ROOT);
    // Upper-casing can decompose or recompose (Greek with iota subscript), so compose again to make
    // the result a fixed point: normalise(normalise(x)) equals normalise(x).
    return Normalizer.normalize(upper, Normalizer.Form.NFC);
  }

  /** Length-prefixed, so that ("ab", "c") and ("a", "bc") are different inputs. */
  private static void put(ByteArrayOutputStream out, String value) {
    byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
    byte[] length = Integer.toString(bytes.length).getBytes(StandardCharsets.UTF_8);
    out.writeBytes(length);
    out.write(':');
    out.writeBytes(bytes);
    out.write('\n');
  }

  private static String sha256(byte[] input) {
    try {
      byte[] digest = MessageDigest.getInstance("SHA-256").digest(input);
      StringBuilder hex = new StringBuilder(64);
      for (byte b : digest) {
        hex.append(Character.forDigit((b >> 4) & 0xf, 16)).append(Character.forDigit(b & 0xf, 16));
      }
      return hex.toString();
    } catch (NoSuchAlgorithmException missing) {
      // Every Java runtime has SHA-256; not having it is a broken JVM, not a case to handle.
      throw new IllegalStateException(missing);
    }
  }
}
