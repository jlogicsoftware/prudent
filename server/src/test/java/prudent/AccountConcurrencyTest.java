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
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;
import prudent.account.AccountEntity;
import prudent.plan.Frequency;
import prudent.plan.PlanEntity;
import prudent.plan.PlanOccurrenceEntity;
import prudent.plan.RecurrenceRule;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.ConfirmOccurrenceRequest;
import prudent.proto.v1.CreateCorrectionRequest;
import prudent.proto.v1.CreatePlanRequest;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.CreateTransferRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.RecurrenceFrequency;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.proto.v1.UpdatePlanRequest;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.record.RecordEntity;

/**
 * Requests that race for one account (jlogicsoftware/prudent#299): an account update or delete holds
 * the account's row for its whole transaction, and everything that writes a record or a plan against
 * the account waits for it, and the other way round. So the check "no record or plan uses the
 * currency being dropped" and the check "the account holds the currency being written" can never
 * both pass on each other's uncommitted state.
 *
 * <p><strong>How a race is made repeatable.</strong> The test holds a database lock (the "gate") that
 * stops the first request after it has done its checks and before it can commit. The second request
 * then starts, and the test releases the gate only once that request has either finished or is
 * itself waiting for a lock. Without the account's lock the second request finishes at once, on stale
 * state; with it, it waits and then reads what the first one committed.
 */
@QuarkusTest
class AccountConcurrencyTest {

  private static final String ALICE = PrudentTest.ALICE;
  private static final String DATE = "2026-10-10";

  @Inject DataSource dataSource;

  /** The account every scenario updates: EUR at position 0, GBP at position 1. */
  private UUID account;

  /** A second account, holding GBP, for the other side of a transfer and as a plan's own. */
  private UUID other;

  private UUID category;
  private ExecutorService pool;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(ALICE, "Travel", "EUR", "GBP");
    other = PrudentTest.seedAccount(ALICE, "Home", "GBP");
    category = PrudentTest.seedCategory(ALICE, "Food");
    pool = Executors.newFixedThreadPool(2);
  }

  @AfterEach
  void stopThreads() throws InterruptedException {
    pool.shutdownNow();
    pool.awaitTermination(30, TimeUnit.SECONDS);
  }

  /** Every way the API writes a record or a plan in a currency against an account. */
  enum Writer {
    RECORD_CREATE("prudent_record", 201),
    RECORD_REPLACE("prudent_record", 200),
    TRANSFER_INTO("prudent_record", 201),
    TRANSFER_OUT_OF("prudent_record", 201),
    CORRECTION("prudent_record", 201),
    OCCURRENCE_CONFIRM("prudent_record", 201),
    PLAN_CREATE("prudent_plan", 201),
    PLAN_REPLACE("prudent_plan", 200);

    /** The table whose write the gate stops. */
    final String table;

    final int success;

    Writer(String table, int success) {
      this.table = table;
      this.success = success;
    }
  }

  /**
   * The race of the issue: two updates of one account. The first rewrites both positions, the second
   * only the one that differs from what it read — so unserialised they merge into [USD, GBP], which
   * neither asked for and which has lost the currency the record is in.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void twoUpdatesOfOneAccount_runOneAfterTheOtherAndKeepTheCurrencyInUse() throws Exception {
    PrudentTest.seedRecord(ALICE, account, category, -500, "EUR");

    Future<Response> first;
    Future<Response> second;
    try (Gate gate = balanceRow(1)) {
      first = pool.submit(() -> update("USD", "EUR"));
      awaitWaiting(first, 1);
      second = pool.submit(() -> update("EUR", "CHF"));
      awaitWaiting(second, 2);
    }

    assertStatus(200, first);
    assertStatus(200, second);
    // The second update's whole set, because it ran after the first and read what it committed.
    assertEquals(List.of("EUR", "CHF"), storedCurrencies(account));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aSecondUpdateThatWouldDropACurrencyInUse_isRefusedAfterTheFirst() throws Exception {
    PrudentTest.seedRecord(ALICE, account, category, -500, "EUR");

    Future<Response> first;
    Future<Response> second;
    try (Gate gate = balanceRow(1)) {
      first = pool.submit(() -> update("USD", "EUR"));
      awaitWaiting(first, 1);
      second = pool.submit(() -> update("USD", "GBP"));
      awaitWaiting(second, 2);
    }

    assertStatus(200, first);
    assertStatus(409, second);
    assertEquals(List.of("USD", "EUR"), storedCurrencies(account));
  }

  @ParameterizedTest
  @EnumSource(Writer.class)
  @TestSecurity(user = PrudentTest.ALICE)
  void aWriteStartedDuringAnUpdateThatDropsItsCurrency_isRefused(Writer writer) throws Exception {
    Prepared write = prepare(writer);

    Future<Response> update;
    Future<Response> written;
    try (Gate gate = balanceRow(1)) {
      update = pool.submit(() -> update("EUR"));
      awaitWaiting(update, 1);
      written = pool.submit(write);
      awaitWaiting(written, 2);
    }

    assertStatus(200, update);
    assertStatus(400, written);
    assertEquals(List.of("EUR"), storedCurrencies(account));
    assertEquals(0, usesOf(account, "GBP"), "nothing may be left in the dropped currency");
  }

  @ParameterizedTest
  @EnumSource(Writer.class)
  @TestSecurity(user = PrudentTest.ALICE)
  void anUpdateDroppingTheCurrencyOfAWriteInProgress_isRefused(Writer writer) throws Exception {
    Prepared write = prepare(writer);

    Future<Response> written;
    Future<Response> update;
    try (Gate gate = table(writer.table)) {
      written = pool.submit(write);
      awaitWaiting(written, 1);
      update = pool.submit(() -> update("EUR"));
      awaitWaiting(update, 2);
    }

    assertStatus(writer.success, written);
    assertStatus(409, update);
    assertEquals(List.of("EUR", "GBP"), storedCurrencies(account));
    assertEquals(1, usesOf(account, "GBP"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aWriteStartedDuringADeleteOfItsAccount_isRefused() throws Exception {
    Prepared write = prepare(Writer.RECORD_CREATE);

    Future<Response> delete;
    Future<Response> written;
    try (Gate gate = balanceRow(1)) {
      delete = pool.submit(() -> delete());
      awaitWaiting(delete, 1);
      written = pool.submit(write);
      awaitWaiting(written, 2);
    }

    assertStatus(204, delete);
    assertStatus(400, written);
    assertEquals(0, usesOf(account, "GBP"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aDeleteOfAnAccountWithAWriteInProgress_isRefused() throws Exception {
    Prepared write = prepare(Writer.RECORD_CREATE);

    Future<Response> written;
    Future<Response> delete;
    try (Gate gate = table("prudent_record")) {
      written = pool.submit(write);
      awaitWaiting(written, 1);
      delete = pool.submit(() -> delete());
      awaitWaiting(delete, 2);
    }

    assertStatus(201, written);
    assertStatus(409, delete);
    assertEquals(List.of("EUR", "GBP"), storedCurrencies(account));
  }

  // --- the requests ---------------------------------------------------------------------------

  /** A request ready to send, with everything it needs already seeded. */
  private interface Prepared extends Callable<Response> {}

  private Prepared prepare(Writer writer) {
    return switch (writer) {
      case RECORD_CREATE ->
          () ->
              post(
                  "/api/v1/records",
                  CreateRecordRequest.newBuilder()
                      .setTitle("Lunch")
                      .setAmountMinor(-500)
                      .setDate(DATE)
                      .setCategoryId(category.toString())
                      .setAccountId(account.toString())
                      .setCurrency("GBP")
                      .build());
      case RECORD_REPLACE -> {
        UUID record = PrudentTest.seedRecord(ALICE, account, category, -500, "EUR");
        yield () ->
            put(
                "/api/v1/records/" + record,
                UpdateRecordRequest.newBuilder()
                    .setTitle("Lunch")
                    .setAmountMinor(-500)
                    .setDate(DATE)
                    .setCategoryId(category.toString())
                    .setAccountId(account.toString())
                    .setCurrency("GBP")
                    .build());
      }
      case TRANSFER_INTO -> () -> transfer(other, account);
      case TRANSFER_OUT_OF -> () -> transfer(account, other);
      case CORRECTION ->
          () ->
              post(
                  "/api/v1/corrections",
                  CreateCorrectionRequest.newBuilder()
                      .setAccountId(account.toString())
                      .setCurrency("GBP")
                      .setBalanceMinor(700)
                      .setDate(DATE)
                      .build());
      case OCCURRENCE_CONFIRM -> {
        // The plan lives on the other account, so only the confirmation names the updated one.
        UUID occurrence = occurrenceOn(seedPlan(other, "GBP"));
        yield () ->
            post(
                "/api/v1/occurrences/" + occurrence + "/confirm",
                ConfirmOccurrenceRequest.newBuilder().setAccountId(account.toString()).build());
      }
      case PLAN_CREATE ->
          () ->
              post(
                  "/api/v1/plans",
                  CreatePlanRequest.newBuilder()
                      .setTitle("Rent")
                      .setAmountMinor(-500)
                      .setCurrency("GBP")
                      .setAccountId(account.toString())
                      .setCategoryId(category.toString())
                      .setRecurrence(once())
                      .build());
      case PLAN_REPLACE -> {
        UUID plan = seedPlan(account, "EUR");
        yield () ->
            put(
                "/api/v1/plans/" + plan,
                UpdatePlanRequest.newBuilder()
                    .setTitle("Rent")
                    .setAmountMinor(-500)
                    .setCurrency("GBP")
                    .setAccountId(account.toString())
                    .setCategoryId(category.toString())
                    .setRecurrence(once())
                    .build());
      }
    };
  }

  private Response transfer(UUID from, UUID to) throws Exception {
    return post(
        "/api/v1/transfers",
        CreateTransferRequest.newBuilder()
            .setFromAccountId(from.toString())
            .setToAccountId(to.toString())
            .setFromAmountMinor(500)
            .setToAmountMinor(500)
            .setFromCurrency("GBP")
            .setToCurrency("GBP")
            .setDate(DATE)
            .build());
  }

  private Response update(String... currencies) throws Exception {
    UpdateAccountRequest.Builder request =
        UpdateAccountRequest.newBuilder()
            .setName("Travel")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsActive(true)
            .setIncludeInTotal(true)
            .setIncludeInOverview(true);
    for (String currency : currencies) {
      request.addBalances(CurrencyBalance.newBuilder().setCurrency(currency));
    }
    return put("/api/v1/accounts/" + account, request.build());
  }

  private Response delete() {
    return PrudentTest.request(PrudentTest.JSON)
        .when()
        .delete("/api/v1/accounts/" + account)
        .andReturn();
  }

  private static Response post(String path, Message body) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, body)
        .when()
        .post(path)
        .andReturn();
  }

  private static Response put(String path, Message body) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, body)
        .when()
        .put(path)
        .andReturn();
  }

  private static Recurrence once() {
    return Recurrence.newBuilder()
        .setFrequency(RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE)
        .setInterval(1)
        .setStartDate(DATE)
        .setTimeZone("Europe/Warsaw")
        .build();
  }

  private UUID seedPlan(UUID onAccount, String currency) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              PlanEntity plan = new PlanEntity();
              plan.id = id;
              plan.userId = UUID.fromString(ALICE);
              plan.title = "Rent";
              plan.amountMinor = -500;
              plan.currency = currency;
              plan.accountId = onAccount;
              plan.categoryId = category;
              plan.setRule(
                  new RecurrenceRule(
                      Frequency.ONCE,
                      1,
                      LocalDate.parse(DATE),
                      ZoneId.of("Europe/Warsaw"),
                      null,
                      null));
              plan.persist();
            });
    return id;
  }

  private static UUID occurrenceOn(UUID plan) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              PlanOccurrenceEntity occurrence = new PlanOccurrenceEntity();
              occurrence.id = id;
              occurrence.userId = UUID.fromString(ALICE);
              occurrence.planId = plan;
              occurrence.occurrenceDate = LocalDate.parse(DATE);
              occurrence.persist();
            });
    return id;
  }

  // --- what is stored -------------------------------------------------------------------------

  private static List<String> storedCurrencies(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                AccountEntity.<AccountEntity>findById(id).balances.stream()
                    .map(balance -> balance.currency)
                    .toList());
  }

  /** How many records and plans name this account in this currency. */
  private static long usesOf(UUID id, String currency) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                RecordEntity.count("accountId = ?1 and currency = ?2", id, currency)
                    + PlanEntity.count("accountId = ?1 and currency = ?2", id, currency));
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

  /** Stops whatever next rewrites or deletes one of the account's balance rows. */
  private Gate balanceRow(int position) throws SQLException {
    return gate(
        "select 1 from prudent_account_balance where account_id = '"
            + account
            + "' and position = "
            + position
            + " for update");
  }

  /** Stops every write to a table, and no read of it. */
  private Gate table(String table) throws SQLException {
    return gate("lock table " + table + " in share mode");
  }

  private Gate gate(String sql) throws SQLException {
    Connection connection = dataSource.getConnection();
    connection.setAutoCommit(false);
    try (Statement statement = connection.createStatement()) {
      statement.execute(sql);
    }
    return new Gate(connection);
  }

  /**
   * Returns once {@code request} has finished, or {@code sessions} database sessions are waiting for
   * a lock — the request's own among them, since the earlier ones were already counted.
   */
  private void awaitWaiting(Future<Response> request, int sessions) throws Exception {
    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30);
    while (!request.isDone() && waitingSessions() < sessions) {
      if (System.nanoTime() > deadline) {
        fail("the request neither finished nor waited for a lock");
      }
      Thread.onSpinWait();
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
