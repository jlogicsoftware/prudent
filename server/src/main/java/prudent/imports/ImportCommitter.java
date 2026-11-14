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
   * @param session the PREVIEWED session being committed, locked by the caller
   * @param accepted its rows whose status is {@link RowStatus#ACCEPTED}, in statement order
   */
  void commit(ImportSessionEntity session, List<ImportRowEntity> accepted);
}
