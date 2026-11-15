package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;

/**
 * A preview stage that exists only in the test classpath, standing in for duplicate detection
 * (jlogicsoftware/prudent#75): an accepted row whose description says DUPLICATEME becomes a
 * duplicate. Proves a stage can classify rows and that the counts and the commit follow.
 */
@ApplicationScoped
public class TestDuplicateStage implements ImportPreviewStage {

  @Override
  public void apply(ImportSessionEntity session, List<ImportRowEntity> rows) {
    for (ImportRowEntity row : rows) {
      if (row.status == RowStatus.ACCEPTED
          && row.description != null
          && row.description.contains("DUPLICATEME")) {
        row.status = RowStatus.DUPLICATE;
      }
    }
  }
}
