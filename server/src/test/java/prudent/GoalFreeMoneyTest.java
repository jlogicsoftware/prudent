package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.CurrencyFreeMoney;
import prudent.proto.v1.GetFreeMoneyResponse;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalAllocationKind;
import prudent.proto.v1.UpdateAccountRequest;
import zen.proto.v1.ZenError;

/**
 * Eligible and free money (M4, jlogicsoftware/prudent#65, ADR-051): which accounts count, what is
 * left once the envelopes are taken off, and the refusal of an allocation beyond it.
 *
 * <p>The envelope actions themselves are {@link GoalAllocationTest}; the arithmetic with no
 * framework around it is {@code prudent.goal.FreeMoneyTest}.
 */
@QuarkusTest
class GoalFreeMoneyTest {

  private static final String ACCOUNTS = "/api/v1/accounts";
  private static final String GOALS = "/api/v1/goals";
  private static final String ALLOCATIONS = "/api/v1/goal-allocations";
  private static final String FREE_MONEY = ALLOCATIONS + "/free-money";

  @BeforeEach
  void seed() {
    PrudentTest.reset();
  }

  // --- Helpers ----------------------------------------------------------------------------------

  private static Goal goal(String name, String currency) throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                CreateGoalRequest.newBuilder()
                    .setName(name)
                    .setCurrency(currency)
                    .setTargetAmountMinor(100_000_00L)
                    .build())
            .when()
            .post(GOALS)
            .andReturn();
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Goal.newBuilder()).build();
  }

  private static Response allocate(Goal target, long amount) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE)
                .setTargetGoalId(target.getId())
                .setAmountMinor(amount)
                .build())
        .when()
        .post(ALLOCATIONS)
        .andReturn();
  }

  private static Response withdraw(Goal source, long amount) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW)
                .setSourceGoalId(source.getId())
                .setAmountMinor(amount)
                .build())
        .when()
        .post(ALLOCATIONS)
        .andReturn();
  }

  private static Response move(Goal source, Goal target, long amount) throws Exception {
    return PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            CreateGoalAllocationRequest.newBuilder()
                .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE)
                .setSourceGoalId(source.getId())
                .setTargetGoalId(target.getId())
                .setAmountMinor(amount)
                .build())
        .when()
        .post(ALLOCATIONS)
        .andReturn();
  }

  private static void accepted(Response response) {
    assertEquals(201, response.statusCode(), response.asString());
  }

  private static ZenError refused(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  private static GetFreeMoneyResponse freeMoney(String mode) throws Exception {
    Response response = PrudentTest.request(mode).when().get(FREE_MONEY).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, GetFreeMoneyResponse.newBuilder()).build();
  }

  private static CurrencyFreeMoney position(String currency) throws Exception {
    return freeMoney(PrudentTest.JSON).getCurrenciesList().stream()
        .filter(p -> p.getCurrency().equals(currency))
        .findFirst()
        .orElseThrow(() -> new AssertionError("no position in " + currency));
  }

  private static long historySize() throws Exception {
    return PrudentTest.decode(
            PrudentTest.JSON,
            PrudentTest.request(PrudentTest.JSON).when().get(ALLOCATIONS).andReturn(),
            prudent.proto.v1.ListGoalAllocationsResponse.newBuilder())
        .build()
        .getAllocationsCount();
  }

  private static Account account(String mode, Response response) throws Exception {
    return PrudentTest.decode(mode, response, Account.newBuilder()).build();
  }

  private static CreateAccountRequest.Builder newAccount(String name, boolean eligible) {
    return CreateAccountRequest.newBuilder()
        .setName(name)
        .setType(AccountType.ACCOUNT_TYPE_SAVINGS)
        .setIsActive(true)
        .setIncludeInTotal(true)
        .setIncludeInOverview(true)
        .setEligibleForGoals(eligible)
        .addBalances(CurrencyBalance.newBuilder().setCurrency("PLN").setAmountMinor(100_00L));
  }

  /** A PUT that changes nothing but the two flags, so the rest of the account is carried over. */
  private static Response replace(Account existing, boolean active, boolean eligible, String mode)
      throws Exception {
    return PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            UpdateAccountRequest.newBuilder()
                .setName(existing.getName())
                .setType(existing.getType())
                .setIsDefault(existing.getIsDefault())
                .setIsActive(active)
                .setIncludeInTotal(existing.getIncludeInTotal())
                .setIncludeInOverview(existing.getIncludeInOverview())
                .setEligibleForGoals(eligible)
                .addAllBalances(existing.getBalancesList())
                .build())
        .when()
        .put(ACCOUNTS + "/" + existing.getId())
        .andReturn();
  }

  // --- Which accounts are eligible --------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void theEligibilityFlagIsSetOnTheAccountAndReadBackIdentically(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, newAccount("Savings", true).build())
            .when()
            .post(ACCOUNTS)
            .andReturn();
    assertEquals(201, created.statusCode(), created.asString());
    Account account = account(mode, created);
    assertTrue(account.getEligibleForGoals());

    Response read =
        PrudentTest.request(mode).when().get(ACCOUNTS + "/" + account.getId()).andReturn();
    assertEquals(account, account(mode, read));

    Response cleared = replace(account, true, false, mode);
    assertEquals(200, cleared.statusCode(), cleared.asString());
    assertFalse(account(mode, cleared).getEligibleForGoals());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAccountIsNotEligibleUnlessTheUserSaysSo() throws Exception {
    Response created =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                newAccount("Plain", false).build())
            .when()
            .post(ACCOUNTS)
            .andReturn();

    assertFalse(account(PrudentTest.JSON, created).getEligibleForGoals());
    assertTrue(freeMoney(PrudentTest.JSON).getCurrenciesList().isEmpty());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aPutThatOmitsTheFlagTurnsItOffBecauseAPutIsAFullReplacement() throws Exception {
    Account account =
        account(
            PrudentTest.JSON,
            PrudentTest.body(
                    PrudentTest.request(PrudentTest.JSON),
                    PrudentTest.JSON,
                    newAccount("Savings", true).build())
                .when()
                .post(ACCOUNTS)
                .andReturn());

    Response omitted =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                UpdateAccountRequest.newBuilder()
                    .setName("Savings")
                    .setType(AccountType.ACCOUNT_TYPE_SAVINGS)
                    .setIsActive(true)
                    .setIncludeInTotal(true)
                    .setIncludeInOverview(true)
                    .addAllBalances(account.getBalancesList())
                    .build())
            .when()
            .put(ACCOUNTS + "/" + account.getId())
            .andReturn();

    assertEquals(200, omitted.statusCode(), omitted.asString());
    assertFalse(account(PrudentTest.JSON, omitted).getEligibleForGoals());
  }

  // --- What is free -----------------------------------------------------------------------------

  @ParameterizedTest(name = "{0}")
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void freeMoneyIsTheEligibleBalancesLessWhatTheEnvelopesHold(String mode) throws Exception {
    UUID savings = PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 800_00L, "PLN");
    UUID cash = PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Cash", 200_00L, "PLN", "EUR");
    PrudentTest.seedAccount(PrudentTest.ALICE, "Checking", "PLN");
    UUID category = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    PrudentTest.seedRecord(PrudentTest.ALICE, cash, category, -50_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, savings, category, 25_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    accepted(allocate(holiday, 300_00L));

    GetFreeMoneyResponse response = freeMoney(mode);

    assertEquals(
        List.of("EUR", "PLN"),
        response.getCurrenciesList().stream().map(CurrencyFreeMoney::getCurrency).toList());
    CurrencyFreeMoney pln = response.getCurrencies(1);
    assertEquals(975_00L, pln.getEligibleMinor(), "800 + 25 + 200 - 50, the checking account is out");
    assertEquals(300_00L, pln.getAllocatedMinor());
    assertEquals(675_00L, pln.getFreeMinor());
    assertEquals(
        List.of(cash.toString(), savings.toString()),
        pln.getEligibleAccountIdsList(),
        "the accounts that make up the figure, in name order");
    CurrencyFreeMoney eur = response.getCurrencies(0);
    assertEquals(200_00L, eur.getEligibleMinor(), "the cash account's EUR pocket, kept apart from PLN");
    assertEquals(200_00L, eur.getFreeMinor());
    assertEquals(List.of(cash.toString()), eur.getEligibleAccountIdsList());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAccountThatIsInactiveOrNoLongerMarkedStopsCounting() throws Exception {
    Account savings =
        account(
            PrudentTest.JSON,
            PrudentTest.body(
                    PrudentTest.request(PrudentTest.JSON),
                    PrudentTest.JSON,
                    newAccount("Savings", true).build())
                .when()
                .post(ACCOUNTS)
                .andReturn());
    assertEquals(100_00L, position("PLN").getFreeMinor());

    assertEquals(200, replace(savings, false, true, PrudentTest.JSON).statusCode());
    assertTrue(freeMoney(PrudentTest.JSON).getCurrenciesList().isEmpty(), "inactive: not counted");

    assertEquals(200, replace(savings, true, true, PrudentTest.JSON).statusCode());
    assertEquals(100_00L, position("PLN").getFreeMinor());

    assertEquals(200, replace(savings, true, false, PrudentTest.JSON).statusCode());
    assertTrue(freeMoney(PrudentTest.JSON).getCurrenciesList().isEmpty(), "unmarked: not counted");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void moneyInACompletedGoalIsStillSetAside() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 500_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    accepted(allocate(holiday, 200_00L));
    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .post(GOALS + "/" + holiday.getId() + "/complete")
            .andReturn()
            .statusCode());

    assertEquals(200_00L, position("PLN").getAllocatedMinor());
    assertEquals(300_00L, position("PLN").getFreeMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anotherUsersAccountsAndEnvelopesAreNotMine() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.BOB, "Bob's savings", 9_999_00L, "PLN");
    UUID bobsGoal = PrudentTest.seedGoal(PrudentTest.BOB, "Bob's car", "PLN", 10_000_00L);
    PrudentTest.seedAllocation(PrudentTest.BOB, bobsGoal, "PLN", 100_00L);
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 50_00L, "PLN");
    Goal mine = goal("Holiday", "PLN");

    CurrencyFreeMoney pln = position("PLN");
    assertEquals(50_00L, pln.getEligibleMinor());
    assertEquals(0L, pln.getAllocatedMinor());

    refused(allocate(mine, 50_01L), 409);
    accepted(allocate(mine, 50_00L));
  }

  // --- The cap ----------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAllocationUpToTheFreeMoneyIsAcceptedAndOneUnitMoreIsNot() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 500_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");

    ZenError error = refused(allocate(holiday, 500_01L), 409);
    assertTrue(error.getMessage().contains("free money"), error.getMessage());
    assertEquals(0, historySize(), "a refused allocation writes nothing");

    accepted(allocate(holiday, 500_00L));
    assertEquals(0L, position("PLN").getFreeMinor());
    refused(allocate(holiday, 1L), 409);
    assertEquals(1, historySize());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theCapIsOnTheTotalAcrossEveryGoalInTheCurrency() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 500_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");

    accepted(allocate(holiday, 300_00L));
    refused(allocate(car, 250_00L), 409);
    accepted(allocate(car, 200_00L));
    refused(allocate(holiday, 1L), 409);
    assertEquals(0L, position("PLN").getFreeMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void nothingIsFreeWhenNoAccountIsEligible() throws Exception {
    PrudentTest.seedAccount(PrudentTest.ALICE, "Checking", "PLN");
    Goal holiday = goal("Holiday", "PLN");

    refused(allocate(holiday, 1L), 409);

    CurrencyFreeMoney pln = position("PLN");
    assertEquals(0L, pln.getEligibleMinor());
    assertEquals(0L, pln.getFreeMinor());
    assertTrue(pln.getEligibleAccountIdsList().isEmpty());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void eligibilityIsPerCurrencyAndNeverBlended() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 1_000_00L, "PLN");
    Goal zloty = goal("Holiday", "PLN");
    Goal euro = goal("Rainy day", "EUR");

    refused(allocate(euro, 1L), 409);
    accepted(allocate(zloty, 1_000_00L));
    assertEquals(0L, position("EUR").getFreeMinor());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aWithdrawalAndAMoveAreNotLimitedByFreeMoneyAndAWithdrawalFreesIt() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 400_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    accepted(allocate(holiday, 400_00L));
    assertEquals(0L, position("PLN").getFreeMinor());

    accepted(move(holiday, car, 150_00L));
    assertEquals(0L, position("PLN").getFreeMinor(), "a move changes no total");

    accepted(withdraw(car, 100_00L));
    assertEquals(100_00L, position("PLN").getFreeMinor());
    accepted(allocate(holiday, 100_00L));
    refused(allocate(holiday, 1L), 409);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void spendingBelowWhatIsAllocatedShowsNegativeFreeMoneyAndRefusesAllocationsUntilItIsReleased()
      throws Exception {
    UUID savings = PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 500_00L, "PLN");
    UUID category = PrudentTest.seedCategory(PrudentTest.ALICE, "Rent");
    Goal holiday = goal("Holiday", "PLN");
    accepted(allocate(holiday, 300_00L));

    PrudentTest.seedRecord(PrudentTest.ALICE, savings, category, -400_00L, "PLN");

    CurrencyFreeMoney over = position("PLN");
    assertEquals(100_00L, over.getEligibleMinor());
    assertEquals(300_00L, over.getAllocatedMinor());
    assertEquals(-200_00L, over.getFreeMinor(), "reported, not hidden and not rewritten");
    refused(allocate(holiday, 1L), 409);

    accepted(withdraw(holiday, 250_00L));
    assertEquals(50_00L, position("PLN").getFreeMinor());
    accepted(allocate(holiday, 50_00L));
    refused(allocate(holiday, 1L), 409);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aRefusedAllocationChangesNoBalanceAndNoEnvelope() throws Exception {
    UUID savings = PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 100_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    String accountBefore =
        PrudentTest.request(PrudentTest.JSON).when().get(ACCOUNTS + "/" + savings).asString();

    refused(allocate(holiday, 100_01L), 409);
    accepted(allocate(holiday, 100_00L));

    assertEquals(
        accountBefore,
        PrudentTest.request(PrudentTest.JSON).when().get(ACCOUNTS + "/" + savings).asString(),
        "setting money aside never moves a balance");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void concurrentAllocationsToDifferentGoalsCannotExceedTheFreeMoney() throws Exception {
    PrudentTest.seedEligibleAccount(PrudentTest.ALICE, "Savings", 300_00L, "PLN");
    Goal holiday = goal("Holiday", "PLN");
    Goal car = goal("Car", "PLN");
    int attempts = 8;
    ExecutorService pool = Executors.newFixedThreadPool(attempts);
    CountDownLatch go = new CountDownLatch(1);
    int created = 0;
    try {
      List<Future<Integer>> results = new ArrayList<>();
      for (int i = 0; i < attempts; i++) {
        Goal target = i % 2 == 0 ? holiday : car;
        results.add(
            pool.submit(
                () -> {
                  go.await();
                  return allocate(target, 100_00L).statusCode();
                }));
      }
      go.countDown();
      for (Future<Integer> result : results) {
        int status = result.get(30, TimeUnit.SECONDS);
        assertTrue(status == 201 || status == 409, "status " + status);
        if (status == 201) {
          created++;
        }
      }
    } finally {
      pool.shutdownNow();
    }

    assertEquals(3, created, "300 free, 100 each: exactly three fit");
    assertEquals(0L, position("PLN").getFreeMinor());
    assertEquals(3, historySize());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAllocationToAnotherUsersGoalIsStillNotFoundNotARefusalAboutMoney() throws Exception {
    UUID bobsGoal = PrudentTest.seedGoal(PrudentTest.BOB, "Bob's car", "PLN", 10_000_00L);

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                CreateGoalAllocationRequest.newBuilder()
                    .setKind(GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE)
                    .setTargetGoalId(bobsGoal.toString())
                    .setAmountMinor(1L)
                    .build())
            .when()
            .post(ALLOCATIONS)
            .andReturn();

    refused(response, 404);
  }

  @Test
  void aCallerWithoutAnIdentityIsRefused() {
    assertEquals(
        401, PrudentTest.request(PrudentTest.JSON).when().get(FREE_MONEY).andReturn().statusCode());
  }
}
