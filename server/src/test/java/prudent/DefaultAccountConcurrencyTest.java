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
import org.junit.jupiter.params.provider.ValueSource;
import prudent.account.AccountEntity;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CreateTransferRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.UpdateAccountRequest;

/**
 * "At most one default account per user" under requests that run at once
 * (jlogicsoftware/prudent#300): requests that ask for the flag take it one after the other, so the
 * later one sees, and clears, what the earlier one committed.
 *
 * <p><strong>How a race is made repeatable.</strong> The test holds a database lock (the "gate") that
 * stops the first request before it can commit. The second request then starts, and the test releases
 * the gate only once that request has either finished or is itself waiting for a lock.
 */
@QuarkusTest
class DefaultAccountConcurrencyTest {

  private static final String ALICE = PrudentTest.ALICE;

  /** The advisory lock key of {@link #commitGate}; the test's own, nothing else takes it. */
  private static final long COMMIT_GATE_KEY = 300_300L;

  @Inject DataSource dataSource;

  /** Two accounts that are not the default. */
  private UUID first;

  private UUID second;

  private ExecutorService pool;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    first = PrudentTest.seedAccount(ALICE, "First", "EUR");
    second = PrudentTest.seedAccount(ALICE, "Second", "EUR");
    pool = Executors.newFixedThreadPool(2);
  }

  @AfterEach
  void stop() throws Exception {
    pool.shutdownNow();
    pool.awaitTermination(30, TimeUnit.SECONDS);
    execute("drop trigger if exists prudent_test_commit_gate on prudent_account");
    execute("drop function if exists prudent_test_commit_gate()");
  }

  /** The two ways to ask for the flag, in every combination and order. */
  enum Pair {
    CREATE_THEN_CREATE(true, true),
    CREATE_THEN_UPDATE(true, false),
    UPDATE_THEN_CREATE(false, true),
    UPDATE_THEN_UPDATE(false, false);

    final boolean firstCreates;
    final boolean secondCreates;

    Pair(boolean firstCreates, boolean secondCreates) {
      this.firstCreates = firstCreates;
      this.secondCreates = secondCreates;
    }
  }

  /** Nobody holds the flag yet, so there is no row the two requests would meet on by themselves. */
  @ParameterizedTest
  @EnumSource(Pair.class)
  @TestSecurity(user = PrudentTest.ALICE)
  void twoRequestsForTheFlag_whenNobodyHoldsIt_leaveOneDefault(Pair pair) throws Exception {
    try (Gate gate = commitGate()) {
      race(gate, pair);
    }
  }

  /** The flag is held: both requests clear the previous holder, and must still see each other. */
  @ParameterizedTest
  @EnumSource(Pair.class)
  @TestSecurity(user = PrudentTest.ALICE)
  void twoRequestsForTheFlag_whenAnotherAccountHoldsIt_leaveOneDefault(Pair pair) throws Exception {
    UUID holder = seedDefault("Holder");
    try (Gate gate = accountRow(holder)) {
      race(gate, pair);
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void takingTheFlagWhileItsHolderIsUpdatedToKeepIt_bothSucceed() throws Exception {
    UUID holder = seedDefault("Holder");

    Future<Response> keep;
    Future<Response> take;
    try (Gate gate = commitGate()) {
      keep = pool.submit(() -> update(holder, true, ""));
      awaitWaiting(keep, 1);
      take = pool.submit(() -> update(first, true, ""));
      awaitWaiting(take, 2);
    }

    assertStatus(200, keep);
    assertStatus(200, take);
    assertEquals(List.of(first), defaults());
  }

  /**
   * One update takes the flag and an account number; the other changes the holder and asks for the
   * same number. The first must hold the holder's row before it writes the number: the other way
   * round each waits for the other, and the database ends one of them as a deadlock (a 500).
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void takingTheFlagWhileItsHolderAsksForTheSameAccountNumber_refusesOneWithoutDeadlock()
      throws Exception {
    UUID holder = seedDefault("Holder");
    String number = "PL61109010140000071219812874";

    Future<Response> take;
    Future<Response> change;
    // Stops the first request at its look for currencies in use: after it has written the number.
    try (Gate gate = gate("lock table prudent_record in access exclusive mode")) {
      take = pool.submit(() -> update(first, true, number));
      awaitWaiting(take, 1);
      change = pool.submit(() -> update(holder, false, number));
      awaitWaiting(change, 2);
    }

    assertStatus(200, take);
    assertStatus(409, change);
    assertEquals(List.of(first), defaults());
  }

  /**
   * A transfer names both accounts the move of the flag writes, so it must not be able to hold one of
   * them while waiting for the other.
   */
  @ParameterizedTest
  @ValueSource(booleans = {true, false})
  @TestSecurity(user = PrudentTest.ALICE)
  void aTransferBetweenTheAccountsWhileTheFlagMoves_succeedsInEitherOrder(boolean transferFirst)
      throws Exception {
    UUID holder = seedDefault("Holder");
    Callable<Response> transfer = () -> transfer(holder, first);
    Callable<Response> take = () -> update(first, true, "");

    Future<Response> earlier;
    Future<Response> later;
    try (Gate gate =
        transferFirst ? gate("lock table prudent_record in share mode") : commitGate()) {
      earlier = pool.submit(transferFirst ? transfer : take);
      awaitWaiting(earlier, 1);
      later = pool.submit(transferFirst ? take : transfer);
      awaitWaiting(later, 2);
    }

    assertStatus(transferFirst ? 201 : 200, earlier);
    assertStatus(transferFirst ? 200 : 201, later);
    assertEquals(List.of(first), defaults());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefusedRequestForTheFlag_leavesItWhereItWas() throws Exception {
    UUID holder = seedDefault("Holder");

    // No currency: refused after the request has already asked for the flag.
    Response update =
        put("/api/v1/accounts/" + first, updateRequest(true, "").clearBalances().build());
    Response create =
        post("/api/v1/accounts", createRequest(true).clearBalances().build());

    assertEquals(400, update.statusCode(), update.asString());
    assertEquals(400, create.statusCode(), create.asString());
    assertEquals(List.of(holder), defaults());
  }

  // --- the race -------------------------------------------------------------------------------

  private void race(Gate gate, Pair pair) throws Exception {
    Future<Response> earlier;
    Future<Response> later;
    try (gate) {
      earlier = pool.submit(ask(pair.firstCreates, first));
      awaitWaiting(earlier, 1);
      later = pool.submit(ask(pair.secondCreates, second));
      awaitWaiting(later, 2);
    }

    assertStatus(pair.firstCreates ? 201 : 200, earlier);
    assertStatus(pair.secondCreates ? 201 : 200, later);
    // The later request's account, because it ran after the earlier one and took the flag from it.
    assertEquals(List.of(idOf(later.get())), defaults());
  }

  private Callable<Response> ask(boolean create, UUID existing) {
    return create
        ? () -> post("/api/v1/accounts", createRequest(true).build())
        : () -> update(existing, true, "");
  }

  private static UUID idOf(Response response) throws Exception {
    return UUID.fromString(
        PrudentTest.decode(PrudentTest.JSON, response, Account.newBuilder()).getId());
  }

  // --- the requests ---------------------------------------------------------------------------

  private static CreateAccountRequest.Builder createRequest(boolean isDefault) {
    return CreateAccountRequest.newBuilder()
        .setName("New")
        .setType(AccountType.ACCOUNT_TYPE_CASH)
        .setIsDefault(isDefault)
        .setIsActive(true)
        .addBalances(CurrencyBalance.newBuilder().setCurrency("EUR"));
  }

  private static UpdateAccountRequest.Builder updateRequest(
      boolean isDefault, String accountNumber) {
    return UpdateAccountRequest.newBuilder()
        .setName("Renamed")
        .setType(AccountType.ACCOUNT_TYPE_CASH)
        .setIsDefault(isDefault)
        .setIsActive(true)
        .setAccountNumber(accountNumber)
        .addBalances(CurrencyBalance.newBuilder().setCurrency("EUR"));
  }

  private static Response update(UUID id, boolean isDefault, String accountNumber)
      throws Exception {
    return put("/api/v1/accounts/" + id, updateRequest(isDefault, accountNumber).build());
  }

  private static Response transfer(UUID from, UUID to) throws Exception {
    return post(
        "/api/v1/transfers",
        CreateTransferRequest.newBuilder()
            .setFromAccountId(from.toString())
            .setToAccountId(to.toString())
            .setFromAmountMinor(5)
            .setToAmountMinor(5)
            .setFromCurrency("EUR")
            .setToCurrency("EUR")
            .setDate("2026-10-10")
            .build());
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

  // --- what is stored -------------------------------------------------------------------------

  private static UUID seedDefault(String name) {
    UUID id = PrudentTest.seedAccount(ALICE, name, "EUR");
    QuarkusTransaction.requiringNew()
        .run(() -> AccountEntity.<AccountEntity>findById(id).isDefault = true);
    return id;
  }

  private static List<UUID> defaults() {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                AccountEntity.listOwnedBy(UUID.fromString(ALICE)).stream()
                    .filter(account -> account.isDefault)
                    .map(account -> account.id)
                    .toList());
  }

  // --- the gate -------------------------------------------------------------------------------

  /** A database lock held by the test; closing it releases the lock. Closing twice is harmless. */
  private static final class Gate implements AutoCloseable {
    private final Connection connection;

    private Gate(Connection connection) {
      this.connection = connection;
    }

    @Override
    public void close() throws SQLException {
      if (connection.isClosed()) {
        return;
      }
      try (connection) {
        connection.rollback();
        connection.setAutoCommit(true);
      }
    }
  }

  /** Stops whatever next writes this account's row. */
  private Gate accountRow(UUID id) throws SQLException {
    return gate("select 1 from prudent_account where id = '" + id + "' for update");
  }

  /**
   * Stops every transaction that inserted or updated an account at its commit, after all it does: a
   * deferred trigger, installed for this test only, that waits for the lock the gate holds.
   */
  private Gate commitGate() throws SQLException {
    execute(
        "create function prudent_test_commit_gate() returns trigger language plpgsql as"
            + " $$ begin perform pg_advisory_xact_lock("
            + COMMIT_GATE_KEY
            + "); return null; end $$");
    execute(
        "create constraint trigger prudent_test_commit_gate after insert or update on"
            + " prudent_account deferrable initially deferred for each row execute function"
            + " prudent_test_commit_gate()");
    return gate("select pg_advisory_xact_lock(" + COMMIT_GATE_KEY + ")");
  }

  private Gate gate(String sql) throws SQLException {
    Connection connection = dataSource.getConnection();
    connection.setAutoCommit(false);
    try (Statement statement = connection.createStatement()) {
      statement.execute(sql);
    }
    return new Gate(connection);
  }

  private void execute(String sql) throws SQLException {
    try (Connection connection = dataSource.getConnection();
        Statement statement = connection.createStatement()) {
      statement.execute(sql);
    }
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
