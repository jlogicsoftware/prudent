package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;

/**
 * The import workflow: parse, preview and commit as three separate, enforced phases (M6,
 * jlogicsoftware/prudent#72, ADR-089). The resource is a thin shell over this; every rule about
 * what may happen when lives here.
 *
 * <ul>
 *   <li><strong>Parse</strong> ({@link #create}) is the only way a session comes to exist. The
 *       importer runs first and everything is written after it returns, in one transaction, so a
 *       statement it rejects — or a bug that throws — leaves no session, no row and no ledger
 *       record. The uploaded bytes are an argument to the importer and go no further: nothing below
 *       takes them, so nothing can store them.
 *   <li><strong>Preview</strong> ({@link #preview}) needs PARSED or PREVIEWED, validates the
 *       destination account, runs the {@link ImportPreviewStage} beans, recounts, and leaves the
 *       session PREVIEWED. Running it again (to change the destination) is allowed because the
 *       uploaded bytes are gone.
 *   <li><strong>Commit</strong> ({@link #commit}) needs PREVIEWED, a destination account that still
 *       passes every check, and the caller's confirmation of exactly the accepted count; it hands
 *       the accepted rows to the {@link ImportCommitter} and, in the same transaction, marks the
 *       session COMMITTED and deletes its rows.
 * </ul>
 *
 * <p><strong>The destination account is validated wherever it is set or replaced, and again at
 * commit</strong> ({@link #requireDestination}, then {@link StatementImporter#checkDestination}):
 * it must be the caller's, active and hold the session's currency, and the importer must accept the
 * statement's identity token for it. Because the statement's own account number is dropped at
 * parse, that identity check cannot live in {@code parse}; running it on every path is what stops a
 * statement parsed for account A from being committed into account B.
 *
 * <p>Every phase change locks the session first ({@link ImportSessionEntity#findOwnedForUpdate}).
 * Ownership is part of that lookup, so another user's session is a 404, never a 403.
 */
@ApplicationScoped
public class ImportWorkflow {

  private static final Logger LOG = Logger.getLogger(ImportWorkflow.class);

  /**
   * The largest statement accepted. A bank export for a personal account is a few kilobytes to a
   * few hundred; a bound keeps one request from making the server hold a large upload in memory.
   */
  static final int MAX_CONTENT_BYTES = 5 * 1024 * 1024;

  /**
   * The most open (PARSED or PREVIEWED) sessions one user may have at once. Each holds personal
   * data until it ends, so an unbounded number would make staging a store. Checked before a parse,
   * so two requests racing each other can overshoot by the number in flight; that is the bound's
   * only slack.
   */
  @ConfigProperty(name = "prudent.import.max-open-sessions", defaultValue = "10")
  int maxOpenSessions;

  /** The most transaction rows one statement may hold ({@link ParsedStatements#validate}). */
  @ConfigProperty(
      name = "prudent.import.max-rows",
      defaultValue = "" + ParsedStatements.DEFAULT_MAX_ROWS)
  int maxRows;

  /** A session and the rows it holds (none once it has ended). */
  public record SessionView(ImportSessionEntity session, List<ImportRowEntity> rows) {}

  @Inject ImportFormats formats;
  @Inject ImportCommitter committer;
  @Inject Instance<ImportPreviewStage> stages;
  @Inject Clock clock;

  /** How long a session can wait for its preview and confirmation before its rows are deleted. */
  @ConfigProperty(name = "prudent.import.session-ttl", defaultValue = "PT24H")
  Duration sessionTtl;

  /** PARSE: runs the named importer and, only if it accepts the statement, opens a session. */
  @Transactional
  public SessionView create(UUID userId, String formatId, byte[] content, UUID accountId) {
    if (content == null || content.length == 0) {
      throw PrudentException.invalid("The statement is empty.");
    }
    if (content.length > MAX_CONTENT_BYTES) {
      throw PrudentException.invalid("The statement is larger than the 5 MiB limit.");
    }
    StatementImporter importer = formats.require(formatId);
    Instant now = clock.instant();
    if (ImportSessionEntity.countOpen(userId, now) >= maxOpenSessions) {
      throw PrudentException.conflict(
          "Too many import sessions are open. Commit or discard one before uploading another.");
    }
    if (accountId != null) {
      requireOwnedAccount(userId, accountId);
    }

    ParsedStatement parsed;
    try {
      parsed = importer.parse(content, new ImportContext(userId, accountId));
      ParsedStatements.validate(importer.formatId(), parsed, maxRows, importer.stableExternalId());
      if (accountId != null) {
        // The statement is parsed, so the currency is known and the destination can be checked in
        // full. Preview checks it again whenever it changes.
        AccountEntity destination = requireDestination(userId, accountId, parsed.currency(), false);
        importer.checkDestination(parsed.accountIdentity(), destination);
      }
    } catch (ImportRejectedException rejected) {
      // The message holds a rule code and a row number and nothing else, by construction.
      throw PrudentException.invalid(rejected.getMessage());
    }

    ImportSessionEntity session = new ImportSessionEntity();
    session.id = UUID.randomUUID();
    session.userId = userId;
    session.formatId = importer.formatId();
    session.state = ImportState.PARSED;
    session.accountId = accountId;
    session.statementIdentity = parsed.accountIdentity();
    session.currency = parsed.currency();
    session.createdAt = now;
    session.stateChangedAt = now;
    session.expiresAt = now.plus(sessionTtl);
    // The session first, so the rows' foreign key is satisfied when they are flushed.
    session.persist();

    List<ImportRowEntity> rows = parsed.rows().stream().map(r -> toEntity(session, r)).toList();
    rows.forEach(row -> row.persist());
    session.recount(rows);
    return new SessionView(session, rows);
  }

  /**
   * Reads one session. A session whose time has run out is expired here if the sweep has not
   * reached it yet, so a read never shows rows that should already be gone.
   *
   * <p>The read takes the same row lock as a phase change, on purpose and not only for the lazy
   * expiry: the session and its rows are two statements, and without the lock a read that lands
   * between a commit's row delete and its commit could show a PREVIEWED session with no rows.
   * Waiting for the in-flight phase change gives a read that is either wholly before it or wholly
   * after.
   */
  @Transactional
  public SessionView get(UUID userId, UUID id) {
    ImportSessionEntity session = ImportSessionEntity.findOwnedForUpdate(userId, id);
    if (session == null) {
      throw PrudentException.notFound("import session", id);
    }
    Instant now = clock.instant();
    if (session.state.holdsRows() && session.isDue(now)) {
      end(session, ImportState.EXPIRED, now);
    }
    List<ImportRowEntity> rows =
        session.state.holdsRows() ? ImportRowEntity.ofSession(userId, id) : List.of();
    return new SessionView(session, rows);
  }

  /**
   * PREVIEW: PARSED or PREVIEWED → PREVIEWED, after the destination has been validated and the
   * preview stages have classified the rows. A second preview is how a user changes the destination
   * without uploading again; it starts from the importer's classification (duplicates are reset) so
   * a stage never inherits a result computed for another account.
   */
  @Transactional
  public SessionView preview(UUID userId, UUID id, UUID accountId) {
    ImportSessionEntity session = lock(userId, id);
    Instant now = clock.instant();
    if (session.state != ImportState.PARSED && session.state != ImportState.PREVIEWED) {
      throw PrudentException.conflict(
          "Only a parsed or previewed import session can be previewed; this one is "
              + session.state
              + ".");
    }
    requireNotDue(session, now);
    // The destination is the one named now, else the one already chosen. Either way it is validated
    // again: the account may have changed since it was chosen, and this is where it can change.
    UUID destinationId = accountId != null ? accountId : session.accountId;
    if (destinationId != null) {
      checkDestination(userId, session, destinationId, false);
      session.accountId = destinationId;
    }

    List<ImportRowEntity> rows = ImportRowEntity.ofSession(userId, id);
    for (ImportRowEntity row : rows) {
      if (row.status == RowStatus.DUPLICATE) {
        row.status = RowStatus.ACCEPTED;
        row.duplicateCode = null;
        row.includeDuplicate = false;
      }
    }
    Map<UUID, RowStatus> before = new HashMap<>();
    rows.forEach(row -> before.put(row.id, row.status));
    for (ImportPreviewStage stage : stages) {
      stage.apply(session, rows);
    }
    for (ImportRowEntity row : rows) {
      // A stage may move a row between ACCEPTED and DUPLICATE. Rejecting is the importer's call and
      // un-rejecting would write a row the importer refused; either is a bug in the stage.
      if ((before.get(row.id) == RowStatus.REJECTED) != (row.status == RowStatus.REJECTED)) {
        throw new IllegalStateException(
            "A preview stage changed whether row " + row.rowNumber + " is rejected.");
      }
    }
    session.recount(rows);
    session.transitionTo(ImportState.PREVIEWED, now);
    return new SessionView(session, rows);
  }

  /**
   * COMMIT: PREVIEWED → COMMITTED, once the committer has written the accepted rows. The caller
   * names how many accepted rows they reviewed; any other number means the preview they saw is not
   * the session that exists, and nothing is written.
   */
  @Transactional
  public SessionView commit(UUID userId, UUID id, int confirmedAcceptedRows) {
    ImportSessionEntity session = lock(userId, id);
    Instant now = clock.instant();
    if (session.state == ImportState.COMMITTED) {
      // A retry of a commit that went through (a lost response, a second click): the same answer,
      // not an error and not a second write. Only the same confirmation counts as a retry; the
      // rows are gone, so the session's own count is what the first commit confirmed.
      if (confirmedAcceptedRows != session.acceptedRows) {
        throw PrudentException.conflict(
            "This import session is already committed with a different number of rows.");
      }
      return new SessionView(session, List.of());
    }
    if (session.state == ImportState.PARSED) {
      throw PrudentException.conflict("Preview the import session before committing it.");
    }
    if (session.state != ImportState.PREVIEWED) {
      throw PrudentException.conflict(
          "Only a previewed import session can be committed; this one is " + session.state + ".");
    }
    requireNotDue(session, now);
    if (session.accountId == null) {
      throw PrudentException.conflict(
          "Choose a destination account for the import before committing it.");
    }
    // The destination is locked before it is checked, so what is checked is what is written to:
    // another request cannot rename, deactivate or re-number it in between, nor can a second commit
    // into it start until this one ends.
    if (AccountEntity.findOwnedForUpdate(userId, session.accountId) == null) {
      throw PrudentException.conflict("The destination account no longer exists.");
    }
    checkDestination(userId, session, session.accountId, true);

    List<ImportRowEntity> accepted =
        ImportRowEntity.ofSession(userId, id).stream().filter(ImportRowEntity::isWritable).toList();
    if (confirmedAcceptedRows != accepted.size()) {
      throw PrudentException.conflict(
          "The confirmed row count does not match the session's accepted rows. Review the"
              + " preview again.");
    }
    // Zero is a valid confirmation: a statement imported in full already has only duplicates, and
    // committing it writes nothing and completes the session instead of forcing a discard.

    // Inside this transaction: if the committer throws, the session stays PREVIEWED and nothing
    // here was written. See ImportCommitter.
    CommitResult result = committer.commit(session, accepted);
    if (result == null || result.written() + result.alreadyImported() != accepted.size()) {
      // A committer that cannot account for every row has lost or invented one; roll back.
      throw new IllegalStateException(
          "The import committer did not account for every accepted row of session " + id + ".");
    }
    session.committedWritten = result.written();
    session.committedAlreadyImported = result.alreadyImported();
    end(session, ImportState.COMMITTED, now);
    return new SessionView(session, List.of());
  }

  /** The answer to a row decision: the changed row and its session, whose counts are current. */
  public record RowDecision(ImportSessionEntity session, ImportRowEntity row) {}

  /**
   * ROW DECISION: sets the category, note or duplicate decision of one held row (ADR-092). Allowed
   * while the session holds rows. A rejected row takes no decision; including a row that is not a
   * duplicate is refused; the category must be the caller's, active and suit the row's direction;
   * the note is at most {@link ImportRowEntity#MAX_NOTE_CHARS} characters. Only the one row is
   * read, and the counts are recomputed (from all rows) only when the inclusion decision changed,
   * so deciding many rows costs each request one row and not the whole statement.
   */
  @Transactional
  public RowDecision updateRow(
      UUID userId, UUID id, int rowNumber, UUID categoryId, boolean clearCategory, String note,
      Boolean includeDuplicate) {
    ImportSessionEntity session = lock(userId, id);
    Instant now = clock.instant();
    if (!session.state.holdsRows()) {
      throw PrudentException.conflict(
          "An import session that is " + session.state + " holds no rows to change.");
    }
    requireNotDue(session, now);
    ImportRowEntity row = ImportRowEntity.findOfSession(userId, id, rowNumber);
    if (row == null) {
      throw PrudentException.notFound("import row", String.valueOf(rowNumber));
    }
    if (row.status == RowStatus.REJECTED) {
      throw PrudentException.conflict("Row " + rowNumber + " was rejected and cannot be changed.");
    }
    String newNote = row.note;
    if (note != null) {
      String trimmed = note.trim();
      if (trimmed.codePointCount(0, trimmed.length()) > ImportRowEntity.MAX_NOTE_CHARS) {
        throw PrudentException.invalid(
            "A note can be at most " + ImportRowEntity.MAX_NOTE_CHARS + " characters.");
      }
      newNote = trimmed.isEmpty() ? null : trimmed;
    }
    if (includeDuplicate != null
        && includeDuplicate
        && row.status != RowStatus.DUPLICATE) {
      throw PrudentException.invalid(
          "Only a row marked as a duplicate can be included; row " + rowNumber + " is not one.");
    }
    if (categoryId != null) {
      row.categoryId = requireCategoryFor(userId, categoryId, row.amountMinor).id;
    } else if (clearCategory) {
      row.categoryId = null;
    }
    row.note = newNote;
    if (includeDuplicate != null && includeDuplicate != row.includeDuplicate) {
      row.includeDuplicate = includeDuplicate;
      session.recount(ImportRowEntity.ofSession(userId, id));
    }
    return new RowDecision(session, row);
  }

  /**
   * DEFAULTS: sets or clears the session-wide default category per direction (ADR-092). Allowed
   * while the session holds rows; each category must be the caller's, active and able to file its
   * direction, exactly as a row's category, and is checked again at commit.
   */
  @Transactional
  public SessionView setDefaults(
      UUID userId,
      UUID id,
      UUID expenseCategoryId,
      boolean clearExpense,
      UUID incomeCategoryId,
      boolean clearIncome) {
    ImportSessionEntity session = lock(userId, id);
    Instant now = clock.instant();
    if (!session.state.holdsRows()) {
      throw PrudentException.conflict(
          "An import session that is " + session.state + " holds no rows to categorise.");
    }
    requireNotDue(session, now);
    if (expenseCategoryId != null) {
      // -1 and +1 stand for "an expense" and "an income" in the kind check.
      session.defaultExpenseCategoryId = requireCategoryFor(userId, expenseCategoryId, -1).id;
    } else if (clearExpense) {
      session.defaultExpenseCategoryId = null;
    }
    if (incomeCategoryId != null) {
      session.defaultIncomeCategoryId = requireCategoryFor(userId, incomeCategoryId, 1).id;
    } else if (clearIncome) {
      session.defaultIncomeCategoryId = null;
    }
    return new SessionView(session, List.of());
  }

  /** The caller's active category that can file an amount of {@code amountMinor}'s sign, or a refusal. */
  private static CategoryEntity requireCategoryFor(UUID userId, UUID categoryId, long amountMinor) {
    CategoryEntity category = CategoryEntity.findOwned(userId, categoryId);
    if (category == null) {
      throw PrudentException.invalid("No such category for this user.");
    }
    category.requireActive();
    category.requireKindFor(amountMinor);
    return category;
  }

  /** DISCARD: the user throws the session away; allowed from any state that still holds rows. */
  @Transactional
  public SessionView discard(UUID userId, UUID id) {
    ImportSessionEntity session = lock(userId, id);
    end(session, ImportState.DISCARDED, clock.instant());
    return new SessionView(session, List.of());
  }

  /**
   * The sweep: expires every session whose time has run out and deletes its rows. Run on a schedule
   * by {@link ImportSessionExpiryJob}; sessions another transaction holds are skipped and caught by
   * the next run.
   *
   * @return how many sessions were expired
   */
  @Transactional
  public int expireDue() {
    Instant now = clock.instant();
    List<ImportSessionEntity> due = ImportSessionEntity.lockDue(now);
    due.forEach(session -> end(session, ImportState.EXPIRED, now));
    if (!due.isEmpty()) {
      LOG.infof("Expired %d import session(s)", due.size());
    }
    return due.size();
  }

  /**
   * Ends a session: moves it to a terminal state and deletes what it holds — its rows, the identity
   * token of the statement's account and the default categories.
   */
  private static void end(ImportSessionEntity session, ImportState terminal, Instant now) {
    session.transitionTo(terminal, now);
    session.statementIdentity = null;
    session.defaultExpenseCategoryId = null;
    session.defaultIncomeCategoryId = null;
    ImportRowEntity.deleteOf(session.userId, session.id);
  }

  private static ImportSessionEntity lock(UUID userId, UUID id) {
    ImportSessionEntity session = ImportSessionEntity.findOwnedForUpdate(userId, id);
    if (session == null) {
      throw PrudentException.notFound("import session", id);
    }
    return session;
  }

  private static void requireNotDue(ImportSessionEntity session, Instant now) {
    if (session.isDue(now)) {
      throw PrudentException.conflict(
          "This import session has expired. Upload the statement again.");
    }
  }

  /**
   * Every rule about a destination account for {@code session}, in one place: the account is the
   * caller's, active and holds the session's currency ({@link #requireDestination}), and the
   * session's importer accepts the statement's identity token for it. A refusal is a 400 when the
   * account came from a request ({@code atCommit} false) and a 409 at commit, where the request was
   * fine and the world changed. The message names a rule and never statement text.
   */
  private void checkDestination(
      UUID userId, ImportSessionEntity session, UUID accountId, boolean atCommit) {
    AccountEntity account = requireDestination(userId, accountId, session.currency, atCommit);
    StatementImporter importer =
        formats
            .find(session.formatId)
            .orElseThrow(
                () ->
                    PrudentException.conflict(
                        "The importer for this session's format is no longer available."));
    try {
      importer.checkDestination(session.statementIdentity, account);
    } catch (ImportRejectedException rejected) {
      throw refusal(atCommit, rejected.getMessage());
    }
  }

  /**
   * The account must be the caller's, active, and hold {@code currency} — the same ownership and
   * {@link AccountEntity#holds} rule {@code RecordWriter}, {@code TransferResource} and {@code
   * CorrectionResource} use, plus active: money is not staged into an account kept only for its
   * history. No statement is at fault here, so the refusal is a {@link PrudentException} and not an
   * {@link ImportRejectedException}.
   */
  private static AccountEntity requireDestination(
      UUID userId, UUID accountId, String currency, boolean atCommit) {
    AccountEntity account = AccountEntity.findOwned(userId, accountId);
    if (account == null) {
      throw refusal(
          atCommit,
          atCommit
              ? "The destination account no longer exists."
              : "No such account for this user.");
    }
    if (!account.isActive) {
      throw refusal(atCommit, "The destination account is inactive.");
    }
    if (!AccountEntity.holds(account, currency)) {
      throw refusal(
          atCommit,
          "The destination account does not hold " + currency + ". Add the currency to it first.");
    }
    return account;
  }

  private static PrudentException refusal(boolean atCommit, String message) {
    return atCommit ? PrudentException.conflict(message) : PrudentException.invalid(message);
  }

  private static void requireOwnedAccount(UUID userId, UUID accountId) {
    if (AccountEntity.findOwned(userId, accountId) == null) {
      // 400, not 404: the id arrived in a request body (see Ids.parseInBody).
      throw PrudentException.invalid("No such account for this user.");
    }
  }

  private static ImportRowEntity toEntity(ImportSessionEntity session, ParsedRow row) {
    ImportRowEntity entity = new ImportRowEntity();
    entity.id = UUID.randomUUID();
    entity.sessionId = session.id;
    entity.userId = session.userId;
    entity.rowNumber = row.rowNumber();
    entity.status = row.isRejected() ? RowStatus.REJECTED : RowStatus.ACCEPTED;
    entity.rejectionCode = row.rejectionCode();
    entity.transactionDate = row.transactionDate();
    entity.bookingDate = row.bookingDate();
    entity.amountMinor = row.amountMinor();
    entity.description = row.description();
    entity.counterparty = row.counterparty();
    entity.counterpartyAccount = row.counterpartyAccount();
    entity.externalId = row.externalId();
    entity.hintCode = row.hintCode();
    return entity;
  }
}
