package prudent.imports;

/**
 * What identifies one statement row inside one account (M6, jlogicsoftware/prudent#75, ADR-091): a
 * digest of what the row says, and which of the rows with that same digest in its statement it is.
 * Stored on the import row at preview and on the ledger record at commit; a row is a duplicate
 * exactly when a record of the destination account already holds its key.
 *
 * @param fingerprint a scheme prefix, a colon and 64 lower-case hex characters (see {@link
 *     RowFingerprints}); never statement text
 * @param occurrence 1-based: the n-th row of the statement with this fingerprint
 */
public record RowKey(String fingerprint, int occurrence) {

  public RowKey {
    if (fingerprint == null || !fingerprint.matches(RowFingerprints.KEY_SHAPE)) {
      throw new IllegalArgumentException("A row key's fingerprint has the wrong shape.");
    }
    if (occurrence < 1) {
      throw new IllegalArgumentException("A row key's occurrence is 1 or more.");
    }
  }
}
