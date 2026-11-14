package prudent.imports;

/** The ids of the formats Prudent intends to support, so a name is spelled in one place. */
public final class ImportFormatIds {

  private ImportFormatIds() {}

  /**
   * Erste Polska's CSV export. <strong>Registration seam:</strong> no importer returns this id yet.
   * jlogicsoftware/prudent#73 adds the {@link StatementImporter} bean that does, and nothing else
   * in the workflow changes for it to be usable.
   */
  public static final String ERSTE_PL_CSV = "erste-pl-csv";
}
