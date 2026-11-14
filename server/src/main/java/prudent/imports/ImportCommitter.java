package prudent.imports;

import java.util.List;

/**
 * The commit-phase seam (M6, jlogicsoftware/prudent#72, ADR-089): where accepted rows become ledger
 * records. <strong>jlogicsoftware/prudent#76 provides the real implementation</strong> — atomic,
 * idempotent, one record per accepted row, written once.
 *
 * <p>The workflow calls it only when the session is PREVIEWED, the caller has confirmed exactly the
 * accepted count, and a destination account is set, <em>inside the same transaction</em> that then
 * moves the session to COMMITTED and deletes its rows. A committer that throws therefore leaves the
 * session PREVIEWED and the ledger untouched; one that returns is final. Implementations must not
 * start a transaction of their own.
 *
 * <p>Until #76 lands the only bean is {@link UnavailableImportCommitter}, which refuses. That is a
 * deliberate placeholder, not a stub that pretends: no import can reach the ledger yet.
 */
public interface ImportCommitter {

  /**
   * Writes {@code accepted} to the ledger of {@code session.userId} in {@code session.accountId}.
   *
   * <p><strong>Idempotence is the committer's job, and the preview's duplicate marks are not
   * enough for it</strong> (ADR-091): they were computed at preview time, and another session of
   * the same file can commit in between. Inside the workflow's single transaction a failed
   * {@code INSERT} aborts the whole Postgres transaction and cannot be caught and continued, so a
   * unique-index violation is not a way to say "already imported". An implementation must
   * serialise on the account (lock its row, {@code SELECT ... FOR UPDATE}), then re-read
   * {@code RecordEntity.importedKeys} and write only the rows whose key is still absent, or use
   * {@code INSERT ... ON CONFLICT DO NOTHING}. The unique index stays as the backstop that turns
   * a bug into a refused write, not a doubled ledger.
   *
   * @param session the PREVIEWED session being committed, locked by the caller
   * @param accepted its rows whose status is {@link RowStatus#ACCEPTED}, in statement order
   * @return the rows written and the rows found already imported; they sum to
   *     {@code accepted.size()}
   */
  CommitResult commit(ImportSessionEntity session, List<ImportRowEntity> accepted);
}
