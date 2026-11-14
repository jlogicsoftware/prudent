package prudent.imports;

import io.quarkus.arc.DefaultBean;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import prudent.error.PrudentException;

/**
 * The commit seam's default bean until jlogicsoftware/prudent#76: it writes nothing and says so.
 * Answers 503 {@code unavailable} (the closest of {@code PrudentException}'s codes to "not built
 * yet"), so the session stays PREVIEWED and the client sees a refusal instead of a success that
 * imported nothing.
 *
 * <p>{@link DefaultBean} so #76's own {@link ImportCommitter} replaces it by existing, with no
 * deletion needed here.
 */
@ApplicationScoped
@DefaultBean
public class UnavailableImportCommitter implements ImportCommitter {

  @Override
  public CommitResult commit(ImportSessionEntity session, List<ImportRowEntity> accepted) {
    throw PrudentException.unavailable("Importing a statement into the ledger is not available yet.");
  }
}
