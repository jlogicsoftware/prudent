package prudent.imports;

/**
 * What the import workflow decided about one row — the persisted form of the wire
 * {@code ImportRowStatus}. Persisted by NAME; the table's {@code CHECK} lists the same names.
 */
public enum RowStatus {
  /** Well formed; written on commit. */
  ACCEPTED,
  /** Recognised as already imported; set only by an {@link ImportPreviewStage}, never written. */
  DUPLICATE,
  /** The importer could not make sense of it; flagged, never dropped silently, never written. */
  REJECTED
}
