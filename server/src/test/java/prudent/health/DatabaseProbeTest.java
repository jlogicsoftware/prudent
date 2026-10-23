package prudent.health;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.lang.reflect.Proxy;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;

class DatabaseProbeTest {

  @Test
  void reachableWhenTheStatementRuns() {
    assertTrue(new DatabaseProbe(dataSource(null, false)).reachable());
  }

  @Test
  void notReachableWhenNoConnectionCanBeTaken() {
    assertFalse(
        new DatabaseProbe(dataSource(new SQLException("host db.internal refused", "08006"), false))
            .reachable());
  }

  @Test
  void notReachableWhenTheStatementFails() {
    assertFalse(new DatabaseProbe(dataSource(null, true)).reachable());
  }

  /** A DataSource that throws {@code connectFailure}, or hands out a fake connection. */
  private static DataSource dataSource(SQLException connectFailure, boolean statementFails) {
    return (DataSource)
        Proxy.newProxyInstance(
            DatabaseProbeTest.class.getClassLoader(),
            new Class<?>[] {DataSource.class},
            (proxy, method, args) -> {
              if (!method.getName().equals("getConnection")) {
                throw new UnsupportedOperationException(method.getName());
              }
              if (connectFailure != null) {
                throw connectFailure;
              }
              return connection(statementFails);
            });
  }

  private static Connection connection(boolean failOnExecute) {
    Statement statement =
        (Statement)
            Proxy.newProxyInstance(
                DatabaseProbeTest.class.getClassLoader(),
                new Class<?>[] {Statement.class},
                (proxy, method, args) -> {
                  if (method.getName().equals("execute") && failOnExecute) {
                    throw new SQLException("canceling statement due to timeout", "57014");
                  }
                  return method.getReturnType() == boolean.class ? Boolean.TRUE : null;
                });
    return (Connection)
        Proxy.newProxyInstance(
            DatabaseProbeTest.class.getClassLoader(),
            new Class<?>[] {Connection.class},
            (proxy, method, args) ->
                method.getName().equals("createStatement") ? statement : null);
  }
}
