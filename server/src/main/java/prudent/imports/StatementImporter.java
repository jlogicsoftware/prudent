package prudent.imports;

import prudent.account.AccountEntity;

/**
 * The importer boundary: one bank statement format (M6, jlogicsoftware/prudent#72, ADR-089).
 *
 * <p>An implementation is an {@code @ApplicationScoped} bean; {@link ImportFormats} finds it and
 * keys it by {@link #formatId()}. <strong>Erste Polska's is the first one and does not exist
 * yet:</strong> jlogicsoftware/prudent#73 adds it, as a bean returning
 * {@link ImportFormatIds#ERSTE_PL_CSV}, validating against {@code docs/erste-csv-contract.md}.
 * Until then that id is unregistered and a request naming it is refused like any unknown format.
 *
 * <p><strong>The contract an importer signs:</strong>
 *
 * <ul>
 *   <li><em>Pure.</em> {@code parse} reads the bytes and returns a {@link ParsedStatement}. It writes
 *       nothing — no ledger row, no session, no log line quoting the statement — so a refusal
 *       cannot leave a partial write behind. It runs inside the workflow's transaction only so that
 *       the session and its rows commit together or not at all.
 *   <li><em>Strict.</em> A variant the format's contract does not describe is rejected as a whole by
 *       throwing {@link ImportRejectedException}, not adapted. The workflow validates what comes
 *       back ({@link ParsedStatements}) and can only add checks; it never relaxes one, so a new
 *       format cannot weaken another format's validation, and sharing the workflow cannot either.
 *   <li><em>No retention.</em> It must not keep the bytes, a copy or a field of them past the call.
 *   <li><em>Identity is a token.</em> The statement's own account number never leaves {@code
 *       parse}: the importer returns {@link ParsedStatement#identityOf} of it, and the workflow asks
 *       {@link #checkDestination} to compare it with the destination account every time one is set
 *       or replaced (parse, preview, re-preview) and again at commit. A destination the user
 *       changes after the parse is therefore checked like the first.
 * </ul>
 */
public interface StatementImporter {

  /**
   * The stable id of the format, e.g. {@code erste-pl-csv}. Lower-case words joined by hyphens
   * ({@link ImportFormats#FORMAT_ID}). It is stored on every session, so renaming one is a data
   * migration.
   */
  String formatId();

  /**
   * Parses one statement.
   *
   * @param content the file exactly as uploaded
   * @param context who is importing and, if chosen, into which account
   * @return the normalised rows; never {@code null}
   * @throws ImportRejectedException when the statement as a whole is not acceptable
   */
  ParsedStatement parse(byte[] content, ImportContext context);

  /**
   * Decides whether {@code destination} may receive this statement. The workflow calls it on every
   * assignment of a destination account and again before commit, with the identity token the parse
   * produced. Throw {@link ImportRejectedException} (a rule such as {@code
   * account.identity_mismatch}; the message can carry no statement text) to refuse.
   *
   * <p><strong>The default checks nothing it could not check, and refuses what it cannot
   * verify.</strong> {@link AccountEntity} has no account-number field yet
   * (jlogicsoftware/prudent#73 adds it together with the Erste implementation of this method), so
   * the default has nothing to compare a token with. For a statement that carries no identity
   * ({@code statementIdentity == null}) it accepts. For one that does, it rejects with {@code
   * account.identity_unverifiable} rather than pass: an importer that returns a token must also say
   * what to compare it with.
   *
   * @param statementIdentity the token from {@link ParsedStatement#accountIdentity()}, or {@code
   *     null} when the format has none
   * @param destination the caller's own account, already checked to be active and to hold the
   *     session's currency
   */
  default void checkDestination(String statementIdentity, AccountEntity destination) {
    if (statementIdentity != null) {
      throw new ImportRejectedException("account.identity_unverifiable");
    }
  }
}
