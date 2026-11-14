package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;
import java.util.regex.Pattern;
import prudent.error.PrudentException;

/**
 * The registry of {@link StatementImporter}s, keyed by format id (M6, jlogicsoftware/prudent#72,
 * ADR-089). Every importer bean is found by CDI, so adding a bank is adding a bean.
 *
 * <p><strong>A broken registry fails the boot, not a request.</strong> Two importers claiming one id,
 * or an id that is not a plain identifier, would otherwise make which parser reads a statement
 * depend on bean ordering — the silent kind of failure this project refuses. The registry throws
 * from its constructor instead.
 */
@ApplicationScoped
public class ImportFormats {

  /** The shape of a format id. */
  public static final Pattern FORMAT_ID = Pattern.compile("[a-z][a-z0-9]*(-[a-z0-9]+)*");

  private final Map<String, StatementImporter> importers;

  @Inject
  public ImportFormats(Instance<StatementImporter> beans) {
    this.importers = index(beans);
  }

  /** For a test that supplies importers directly; the application uses the CDI constructor. */
  ImportFormats(List<StatementImporter> importers) {
    this.importers = index(importers);
  }

  private static Map<String, StatementImporter> index(Iterable<StatementImporter> beans) {
    Map<String, StatementImporter> found = new TreeMap<>();
    for (StatementImporter importer : beans) {
      String id = importer.formatId();
      if (id == null || !FORMAT_ID.matcher(id).matches()) {
        throw new IllegalStateException(
            importer.getClass().getName() + " has a format id that is not a plain identifier");
      }
      StatementImporter earlier = found.put(id, importer);
      if (earlier != null) {
        throw new IllegalStateException(
            "Two importers claim the format id '"
                + id
                + "': "
                + earlier.getClass().getName()
                + " and "
                + importer.getClass().getName());
      }
    }
    return Map.copyOf(found);
  }

  /** The ids that can be named in a request, sorted. */
  public List<String> ids() {
    return importers.keySet().stream().sorted().toList();
  }

  /** The importer for {@code formatId}, if one is registered; no error and no echo of the id. */
  public Optional<StatementImporter> find(String formatId) {
    return Optional.ofNullable(formatId == null ? null : importers.get(formatId));
  }

  /**
   * The importer for {@code formatId}, or a 400 that lists what is supported. The requested id is
   * not echoed back: it is caller-supplied text.
   */
  public StatementImporter require(String formatId) {
    StatementImporter importer = formatId == null ? null : importers.get(formatId);
    if (importer == null) {
      throw PrudentException.invalid(
          "Unsupported import format. Supported formats: "
              + (importers.isEmpty() ? "none" : String.join(", ", ids()))
              + ".");
    }
    return importer;
  }
}
