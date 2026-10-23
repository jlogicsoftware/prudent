package prudent.health;

import io.quarkus.logging.Log;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import javax.sql.DataSource;
import prudent.error.ServerFailureReport;

/**
 * Asks the database one question that touches no table: can a connection be taken and a statement
 * run on it.
 *
 * <p><strong>No table is read on purpose.</strong> The probe is anonymous, so anything it touched
 * would be reachable by anyone, and the tables are the user's money. {@code SELECT 1} proves the
 * thing a readiness check is for — the service can reach its database — and nothing about the
 * data.
 *
 * <p><strong>The failure is logged by class and SQLSTATE, never by message.</strong> A driver's
 * message can quote a host, a role or a row; {@link ServerFailureReport} is the one place that
 * decides what of a failure is safe to write down.
 */
@ApplicationScoped
public class DatabaseProbe {

  /** Seconds the statement may take. A database that answers slower than this is not ready. */
  static final int TIMEOUT_SECONDS = 2;

  private final DataSource dataSource;

  @Inject
  public DatabaseProbe(DataSource dataSource) {
    this.dataSource = dataSource;
  }

  /** Whether the database answered. Never throws: a probe that throws is a probe that 500s. */
  public boolean reachable() {
    try (Connection connection = dataSource.getConnection();
        Statement statement = connection.createStatement()) {
      statement.setQueryTimeout(TIMEOUT_SECONDS);
      statement.execute("SELECT 1");
      return true;
    } catch (SQLException | RuntimeException e) {
      Log.warnf("Readiness probe failed: %s", ServerFailureReport.describeFailure(e));
      return false;
    }
  }
}
