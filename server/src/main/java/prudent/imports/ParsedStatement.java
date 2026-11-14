package prudent.imports;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;

/**
 * What an importer produces from one statement: the currency every row is in, the rows, and an
 * opaque token for the account the statement is about. It is the only thing that crosses from a
 * parser into the workflow, and it holds no bytes of the file, so nothing the workflow persists can
 * contain the original (ADR-089).
 *
 * <p><strong>The account identity is a token, not the account number.</strong> A statement carries
 * the number of the account it describes (and a holder's name); neither is a field here. What the
 * importer hands over instead is {@link #identityOf}: a SHA-256 digest of the normalised number, or
 * {@code null} when the format carries no account identity. The workflow keeps the token with the
 * session and gives it back to {@link StatementImporter#checkDestination} whenever a destination
 * account is set or replaced, so the check runs on every path and not only at parse. It is a
 * digest, not encryption: an unsalted digest of a short, structured number can be guessed, so it is
 * treated as personal data. It is never sent over the wire, never logged and cleared when the
 * session ends.
 *
 * @param accountIdentity {@link #identityOf} of the statement's own account, or {@code null}
 */
public record ParsedStatement(String currency, List<ParsedRow> rows, String accountIdentity) {

  /** A statement from a format that carries no account identity. */
  public ParsedStatement(String currency, List<ParsedRow> rows) {
    this(currency, rows, null);
  }

  /**
   * The identity token of an account number: whitespace removed, upper-cased, SHA-256, lower-case
   * hex (64 characters). Importers and {@link StatementImporter#checkDestination} implementations
   * use this one function so that a token compares equal exactly when the numbers do.
   */
  public static String identityOf(String accountNumber) {
    if (accountNumber == null) {
      throw new IllegalArgumentException("an account number is required to derive its identity");
    }
    String normalised = accountNumber.replaceAll("\\s+", "").toUpperCase(Locale.ROOT);
    if (normalised.isEmpty()) {
      throw new IllegalArgumentException("an account number is required to derive its identity");
    }
    try {
      byte[] digest =
          MessageDigest.getInstance("SHA-256").digest(normalised.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(digest);
    } catch (NoSuchAlgorithmException impossible) {
      throw new IllegalStateException("SHA-256 is required of every Java runtime", impossible);
    }
  }
}
