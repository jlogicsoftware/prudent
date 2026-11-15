package prudent.imports;

/** The ids of the formats Prudent intends to support, so a name is spelled in one place. */
public final class ImportFormatIds {

  private ImportFormatIds() {}

  /**
   * Erste Polska's CSV export, read by {@link ErsteStatementImporter} (jlogicsoftware/prudent#73,
   * ADR-090).
   */
  public static final String ERSTE_PL_CSV = "erste-pl-csv";
}
