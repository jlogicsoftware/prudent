package prudent.imports;

/**
 * What an {@link ImportCommitter} reports: how many accepted rows it wrote and how many it found
 * already in the ledger (M6, jlogicsoftware/prudent#75, ADR-091). Between them they account for
 * every accepted row it was given, which the workflow checks.
 *
 * <p>The second number is not an error. A preview is advice: two tabs, or a retry after a timeout,
 * can commit sessions of the same file, and the later one must write nothing rather than double
 * the ledger.
 *
 * @param written records created by this commit
 * @param alreadyImported accepted rows whose key a record of the account already held when the
 *     committer looked, under its lock
 */
public record CommitResult(int written, int alreadyImported) {

  public CommitResult {
    if (written < 0 || alreadyImported < 0) {
      throw new IllegalArgumentException("A commit cannot report a negative count.");
    }
  }
}
