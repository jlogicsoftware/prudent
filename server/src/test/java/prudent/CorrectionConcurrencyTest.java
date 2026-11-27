package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.fail;

import com.google.protobuf.Message;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateCorrectionRequest;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.CreateTransferRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.record.RecordEntity;

/**
 * Requests that race with a balance correction (jlogicsoftware/prudent#301). A correction stores
 * the difference between the balance asked for and the balance it read, so whatever changes that
 * balance by adding to it must run wholly before the read or wholly after the insert.
 *
 * <p><strong>How a race is made repeatable.</strong> The test holds a database lock (the "gate")
 * that stops every write to the records table, so the first request stops after it has read and
 * before it can insert. The second request then starts, and the gate is released only once that
 * request has either finished or is itself waiting for a lock.
 */
@QuarkusTest
class CorrectionConcurrencyTest {

  private static final String ALICE = PrudentTest.ALICE;
  private static final String DATE = "2026-10-10";

  @Inject DataSource dataSource;

  /** The account corrected, holding EUR. */
  private UUID account;

  /** A second account holding EUR, for the other side of a transfer. */
  private UUID other;

  private UUID category;
  private ExecutorService pool;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(ALICE, "Travel", "EUR");
    other = PrudentTest.seedAccount(ALICE, "Home", "EUR");
    category = PrudentTest.seedCategory(ALICE, "Food");
    pool = Executors.newFixedThreadPool(3);
  }

  @AfterEach
  void stopThreads() throws InterruptedException {
    pool.shutdownNow();
    pool.awaitTermination(30, TimeUnit.SECONDS);
  }

  /** The race of the issue: both compute their difference from the same balance. */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void twoCorrectionsToOneTarget_applyTheDifferenceOnce() throws Exception {
    Future<Response> first;
    Future<Response> second;
    try (Gate gate = recordWrites()) {
      first = pool.submit(() -> correct(account, 700));
      awaitWaiting(first);
      second = pool.submit(() -> correct(account, 700));
      awaitWaiting(second, first);
    }

    assertStatus(201, first);
    // It ran after the first, found the balance already there and had nothing to correct.
    assertStatus(400, second);
    assertEquals(700, balanceOf(account));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void twoCorrectionsToDifferentTargets_endAtTheSecondOne() throws Exception {
    Future<Response> first;
    Future<Response> second;
    try (Gate gate = recordWrites()) {
      first = pool.submit(() -> correct(account, 700));
      awaitWaiting(first);
      second = pool.submit(() -> correct(account, 900));
      awaitWaiting(second, first);
    }

    assertStatus(201, first);
    assertStatus(201, second);
    assertEquals(900, balanceOf(account));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCorrectionStartedDuringARecordWrite_countsThatRecord() throws Exception {
    Future<Response> written;
    Future<Response> correction;
    try (Gate gate = recordWrites()) {
      written = pool.submit(() -> record(account));
      awaitWaiting(written);
      correction = pool.submit(() -> correct(account, 700));
      awaitWaiting(correction, written);
    }

    assertStatus(201, written);
    assertStatus(201, correction);
    assertEquals(700, balanceOf(account));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCorrectionStartedDuringATransferIntoTheAccount_countsThatLeg() throws Exception {
    Future<Response> transfer;
    Future<Response> correction;
    try (Gate gate = recordWrites()) {
      transfer = pool.submit(() -> transfer(other, account));
      awaitWaiting(transfer);
      correction = pool.submit(() -> correct(account, 700));
      awaitWaiting(correction, transfer);
    }

    assertStatus(201, transfer);
    assertStatus(201, correction);
    assertEquals(700, balanceOf(account));
  }

  /** The other order: the record is added to the corrected balance, not lost in it. */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRecordWrittenDuringACorrection_isAddedAfterIt() throws Exception {
    Future<Response> correction;
    Future<Response> written;
    try (Gate gate = recordWrites()) {
      correction = pool.submit(() -> correct(account, 700));
      awaitWaiting(correction);
      written = pool.submit(() -> record(account));
      awaitWaiting(written, correction);
    }

    assertStatus(201, correction);
    assertStatus(201, written);
    assertEquals(200, balanceOf(account));
  }

  /**
   * An update that makes another account the default also writes the row of the account that was
   * the default, which here is the one being corrected, while a transfer out of it needs the
   * updated account. None of the three may end in a deadlock.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCorrectionADefaultMoveAndATransfer_allFinish() throws Exception {
    assertEquals(200, update(account, "Travel").statusCode());

    Future<Response> correction;
    Future<Response> moved;
    Future<Response> transfer;
    try (Gate gate = recordWrites()) {
      correction = pool.submit(() -> correct(account, 700));
      awaitWaiting(correction);
      moved = pool.submit(() -> update(other, "Home"));
      awaitWaiting(moved, correction);
      transfer = pool.submit(() -> transfer(account, other));
      awaitWaiting(transfer, correction, moved);
    }

    assertStatus(201, correction);
    assertStatus(200, moved);
    assertStatus(201, transfer);
    assertEquals(200, balanceOf(account));
  }

  // --- the requests ---------------------------------------------------------------------------

  private static Response correct(UUID on, long target) throws Exception {
    return post(
        "/api/v1/corrections",
        CreateCorrectionRequest.newBuilder()
            .setAccountId(on.toString())
            .setCurrency("EUR")
            .setBalanceMinor(target)
            .setDate(DATE)
            .build());
  }

  /** An expense of 500 on the account. */
  private Response record(UUID on) throws Exception {
    return post(
        "/api/v1/records",
        CreateRecordRequest.newBuilder()
            .setTitle("Lunch")
            .setAmountMinor(-500)
            .setDate(DATE)
            .setCategoryId(category.toString())
            .setAccountId(on.toString())
            .setCurrency("EUR")
            .build());
  }

  /** A transfer of 500. */
  private static Response transfer(UUID from, UUID to) throws Exception {
    return post(
        "/api/v1/transfers",
        CreateTransferRequest.newBuilder()
            .setFromAccountId(from.toString())
            .setToAccountId(to.toString())
            .setFromAmountMinor(500)
            .setToAmountMinor(500)
            .setFromCurrency("EUR")
            .setToCurrency("EUR")
            .setDate(DATE)
            .build());
  }

  /** Replaces the account, making it the default one. */
  private static Response update(UUID id, String name) throws Exception {
    UpdateAccountRequest request =
        UpdateAccountRequest.newBuilder()
            .setName(name)
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsDefault(true)
            .setIsActive(true)
            .setIncludeInTotal(true)
            .setIncludeInOverview(true)
            .addBalances(CurrencyBalance.newBuilder().setCurrency("EUR"))
            .build();
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request)
        .when()
        .put("/api/v1/accounts/" + id)
        .andReturn();
  }

  private static Response post(String path, Message body) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, body)
        .when()
        .post(path)
        .andReturn();
  }

  // --- what is stored -------------------------------------------------------------------------

  /** The account's EUR balance. It opens at zero, so this is the net of its records. */
  private static long balanceOf(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                RecordEntity.netByAccount(UUID.fromString(ALICE), id).getOrDefault("EUR", 0L));
  }

  // --- the gate -------------------------------------------------------------------------------

  /** A database lock held by the test; closing it releases the lock. */
  private static final class Gate implements AutoCloseable {
    private final Connection connection;

    private Gate(Connection connection) {
      this.connection = connection;
    }

    @Override
    public void close() throws SQLException {
      try (connection) {
        connection.rollback();
        connection.setAutoCommit(true);
      }
    }
  }

  /** Stops every write to the records table, and no read of it. */
  private Gate recordWrites() throws SQLException {
    Connection connection = dataSource.getConnection();
    connection.setAutoCommit(false);
    try (Statement statement = connection.createStatement()) {
      statement.execute("lock table prudent_record in share mode");
    }
    return new Gate(connection);
  }

  /**
   * Returns once {@code request} has finished, or is itself waiting for a lock: that is, more
   * database sessions wait than there are unfinished {@code earlier} requests.
   */
  private void awaitWaiting(Future<Response> request, Future<?>... earlier) throws Exception {
    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
    while (!request.isDone()
        && waitingSessions() <= Arrays.stream(earlier).filter(one -> !one.isDone()).count()) {
      if (System.nanoTime() > deadline) {
        fail("the request neither finished nor waited for a lock");
      }
      TimeUnit.MILLISECONDS.sleep(20);
    }
  }

  private int waitingSessions() throws SQLException {
    try (Connection connection = dataSource.getConnection();
        PreparedStatement query =
            connection.prepareStatement(
                "select count(*) from pg_stat_activity"
                    + " where datname = current_database() and wait_event_type = 'Lock'");
        ResultSet result = query.executeQuery()) {
      result.next();
      return result.getInt(1);
    }
  }

  private static void assertStatus(int expected, Future<Response> request) throws Exception {
    Response response = request.get(60, TimeUnit.SECONDS);
    assertEquals(expected, response.statusCode(), response.asString());
  }
}
