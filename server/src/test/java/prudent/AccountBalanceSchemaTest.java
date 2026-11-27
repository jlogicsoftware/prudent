package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Migration coverage for {@code prudent_account_balance_unique_currency} (V20261127185652,
 * jlogicsoftware/prudent#261): one balance per currency per account is checked at commit, so a
 * transaction may pass through a duplicate and still may not leave one behind.
 *
 * <p>Plain SQL through the owner connection on purpose — what the schema does when no validator
 * stands in front of it.
 */
@QuarkusTest
class AccountBalanceSchemaTest {

  @Inject DataSource dataSource;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  private static String setCurrency(UUID account, int position, String currency) {
    return "UPDATE prudent_account_balance SET currency = '"
        + currency
        + "' WHERE account_id = '"
        + account
        + "' AND position = "
        + position;
  }

  @Test
  void twoPositionsMaySwapCurrenciesInOneTransaction() throws SQLException {
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "EUR", "PLN");
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      owner.setAutoCommit(false);
      // Between these two statements both rows hold PLN.
      statement.executeUpdate(setCurrency(account, 0, "PLN"));
      statement.executeUpdate(setCurrency(account, 1, "EUR"));
      owner.commit();
      owner.setAutoCommit(true);
    }
  }

  @Test
  void aDuplicateCurrencyIsStillRefusedAtCommit() throws SQLException {
    UUID account = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "EUR", "PLN");
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      owner.setAutoCommit(false);
      statement.executeUpdate(setCurrency(account, 0, "PLN"));

      SQLException refused = assertThrows(SQLException.class, owner::commit);

      assertEquals("23505", refused.getSQLState());
      assertTrue(
          refused.getMessage().contains("prudent_account_balance_unique_currency"),
          "expected a violation of the currency constraint, got: " + refused.getMessage());
      owner.rollback();
      owner.setAutoCommit(true);
    }
  }
}
