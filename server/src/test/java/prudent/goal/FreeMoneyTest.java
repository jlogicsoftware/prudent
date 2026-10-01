package prudent.goal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;

/**
 * Eligible, allocated and free money with no framework around them (M4, jlogicsoftware/prudent#65,
 * ADR-051): which accounts count, how balances combine and how a goal's envelope is taken off.
 */
class FreeMoneyTest {

  private static AccountEntity account(
      String name, boolean eligible, boolean active, AccountBalance... balances) {
    AccountEntity account = new AccountEntity();
    account.id = UUID.randomUUID();
    account.name = name;
    account.eligibleForGoals = eligible;
    account.isActive = active;
    account.balances.addAll(List.of(balances));
    return account;
  }

  private static GoalEntity goal(String currency) {
    GoalEntity goal = new GoalEntity();
    goal.id = UUID.randomUUID();
    goal.currency = currency;
    return goal;
  }

  private static Map<String, FreeMoney.Position> calculate(
      List<AccountEntity> accounts,
      Map<UUID, Map<String, Long>> net,
      List<GoalEntity> goals,
      Map<UUID, Long> envelopes) {
    return FreeMoney.calculate(accounts, net, goals, envelopes);
  }

  @Test
  void anAccountFundsGoalsOnlyWhenItIsEligibleAndActive() {
    assertTrue(account("a", true, true, new AccountBalance("PLN", 1)).fundsGoals());
    assertFalse(account("a", false, true, new AccountBalance("PLN", 1)).fundsGoals());
    assertFalse(account("a", true, false, new AccountBalance("PLN", 1)).fundsGoals());
    assertFalse(account("a", false, false, new AccountBalance("PLN", 1)).fundsGoals());
  }

  @Test
  void nothingIsEligibleWhenNoAccountIsMarked() {
    var positions =
        calculate(
            List.of(account("Cash", false, true, new AccountBalance("PLN", 500_00))),
            Map.of(),
            List.of(),
            Map.of());

    assertTrue(positions.isEmpty(), "a currency nothing names is absent");
  }

  @Test
  void eligibleMoneyIsTheOpeningBalanceAndTheRecordsOfEachEligibleAccount() {
    AccountEntity savings = account("Savings", true, true, new AccountBalance("PLN", 1_000_00));
    AccountEntity cash = account("Cash", true, true, new AccountBalance("PLN", 200_00));
    AccountEntity hidden = account("Checking", false, true, new AccountBalance("PLN", 9_999_00));
    AccountEntity closed = account("Old", true, false, new AccountBalance("PLN", 9_999_00));

    var positions =
        calculate(
            List.of(savings, cash, hidden, closed),
            Map.of(
                savings.id, Map.of("PLN", -150_00L),
                cash.id, Map.of("PLN", 50_00L),
                hidden.id, Map.of("PLN", 1L)),
            List.of(),
            Map.of());

    FreeMoney.Position pln = positions.get("PLN");
    assertEquals(1_100_00L, pln.eligibleMinor(), "1000 - 150 + 200 + 50");
    assertEquals(0L, pln.allocatedMinor());
    assertEquals(1_100_00L, pln.freeMinor());
  }

  @Test
  void theAccountsThatMakeUpAPositionAreListedInNameOrder() {
    AccountEntity zeta = account("Zeta", true, true, new AccountBalance("PLN", 1));
    AccountEntity alpha = account("Alpha", true, true, new AccountBalance("PLN", 1));
    AccountEntity skipped = account("Beta", false, true, new AccountBalance("PLN", 1));

    var positions = calculate(List.of(zeta, skipped, alpha), Map.of(), List.of(), Map.of());

    assertEquals(List.of(alpha.id, zeta.id), positions.get("PLN").eligibleAccountIds());
  }

  @Test
  void currenciesAreKeptApartAndListedByCode() {
    AccountEntity travel =
        account(
            "Travel", true, true, new AccountBalance("USD", 10_00), new AccountBalance("EUR", 20_00));
    AccountEntity savings = account("Savings", true, true, new AccountBalance("PLN", 30_00));

    var positions = calculate(List.of(travel, savings), Map.of(), List.of(), Map.of());

    assertEquals(List.of("EUR", "PLN", "USD"), List.copyOf(positions.keySet()));
    assertEquals(20_00L, positions.get("EUR").eligibleMinor());
    assertEquals(30_00L, positions.get("PLN").eligibleMinor());
    assertEquals(10_00L, positions.get("USD").eligibleMinor());
  }

  @Test
  void anEnvelopeIsTakenOffItsOwnCurrencyOnly() {
    AccountEntity savings =
        account("Savings", true, true, new AccountBalance("PLN", 500_00), new AccountBalance("EUR", 80_00));
    GoalEntity holiday = goal("PLN");
    GoalEntity car = goal("PLN");
    GoalEntity rainyDay = goal("EUR");

    var positions =
        calculate(
            List.of(savings),
            Map.of(),
            List.of(holiday, car, rainyDay),
            Map.of(holiday.id, 120_00L, car.id, 30_00L, rainyDay.id, 5_00L));

    assertEquals(150_00L, positions.get("PLN").allocatedMinor());
    assertEquals(350_00L, positions.get("PLN").freeMinor());
    assertEquals(5_00L, positions.get("EUR").allocatedMinor());
    assertEquals(75_00L, positions.get("EUR").freeMinor());
  }

  @Test
  void aGoalWithNoEntriesAddsNothingButNamesItsCurrency() {
    var positions =
        calculate(List.of(), Map.of(), List.of(goal("CHF")), Map.of());

    FreeMoney.Position chf = positions.get("CHF");
    assertEquals(0L, chf.eligibleMinor());
    assertEquals(0L, chf.allocatedMinor());
    assertEquals(0L, chf.freeMinor());
    assertTrue(chf.eligibleAccountIds().isEmpty());
  }

  @Test
  void freeMoneyIsNegativeWhenTheEnvelopesHoldMoreThanTheEligibleAccounts() {
    AccountEntity savings = account("Savings", true, true, new AccountBalance("PLN", 100_00));
    GoalEntity holiday = goal("PLN");

    var positions =
        calculate(List.of(savings), Map.of(), List.of(holiday), Map.of(holiday.id, 300_00L));

    assertEquals(-200_00L, positions.get("PLN").freeMinor());
  }

  @Test
  void anOverdrawnEligibleAccountOffsetsTheOnesInCredit() {
    AccountEntity savings = account("Savings", true, true, new AccountBalance("PLN", 400_00));
    AccountEntity card = account("Card", true, true, new AccountBalance("PLN", -150_00));

    var positions = calculate(List.of(savings, card), Map.of(), List.of(), Map.of());

    assertEquals(250_00L, positions.get("PLN").eligibleMinor());
  }

  @Test
  void aGoalWhoseCurrencyNoEligibleAccountHoldsHasNoFreeMoney() {
    AccountEntity savings = account("Savings", true, true, new AccountBalance("PLN", 500_00));

    var positions = calculate(List.of(savings), Map.of(), List.of(goal("EUR")), Map.of());

    assertEquals(0L, positions.get("EUR").freeMinor(), "PLN cannot cover EUR");
  }
}
