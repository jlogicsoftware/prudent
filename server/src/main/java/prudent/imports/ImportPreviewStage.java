package prudent.imports;

import java.util.List;

/**
 * An extension point of the preview phase (M6, jlogicsoftware/prudent#72, ADR-089): code that
 * classifies or annotates the held rows before the user sees them. Every {@code ImportPreviewStage}
 * bean runs once per preview, inside its transaction, and the session's counts are recounted
 * afterwards.
 *
 * <p>Duplicate detection (jlogicsoftware/prudent#75) is the intended first stage: it marks rows
 * {@link RowStatus#DUPLICATE}. A stage may only change a row's status between ACCEPTED and
 * DUPLICATE — it cannot reject a row (that is the importer's call), and it cannot make a rejected
 * row writable, which {@link ImportWorkflow} enforces rather than trusts. Stages run in no
 * guaranteed order, so each must depend only on the session, the rows and the database.
 *
 * <p>A session can be previewed again (PREVIEWED to PREVIEWED, e.g. after the destination account
 * changed). The workflow therefore sets every {@link RowStatus#DUPLICATE} row back to ACCEPTED
 * before the stages run, so a stage always starts from the importer's classification and its result
 * never depends on an earlier preview of another destination.
 */
public interface ImportPreviewStage {

  /**
   * @param session the session being previewed, locked by the caller
   * @param rows all of its rows, in statement order, as managed entities
   */
  void apply(ImportSessionEntity session, List<ImportRowEntity> rows);
}
