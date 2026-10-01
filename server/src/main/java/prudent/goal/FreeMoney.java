package prudent.goal;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.record.RecordEntity;

/**
 * What a user may still set aside for goals, per currency (M4, jlogicsoftware/prudent#65,
 * ADR-051). Calculated on every call and stored nowhere, so it cannot disagree with the balances
 * and envelopes it is made of.
 *
 * <p><strong>Eligible</strong> money is the current balance, in one currency, of every account that
 * {@linkplain AccountEntity#fundsGoals funds goals} — the same derived balance an account answers
 * with (opening amount plus the sum of its records). <strong>Allocated</strong> money is what the
 * goals' envelopes hold in that currency, whatever state the goals are in: money in a completed
 * goal is still set aside until it is withdrawn. <strong>Free</strong> money is the first less the
 * second.
 *
 * <p>Per currency and never blended: there is no FX (ADR-009), so a surplus in one currency cannot
 * cover an allocation in another.
 *
 * <p>{@link #calculate} is the rule with no framework around it, so it is tested alone; {@link
 * #forUser} and {@link #positionIn} only gather its inputs.
 */
public final class FreeMoney {

  private FreeMoney() {}

  /**
   * One currency's figures.
   *
   * @param eligibleAccountIds the accounts that make up {@code eligibleMinor}, in name order
   */
  public record Position(
      String currency, long eligibleMinor, long allocatedMinor, List<UUID> eligibleAccountIds) {

    /**
     * Eligible less allocated. Negative when the envelopes hold more than the eligible accounts
     * do, which a later spend or an account leaving the eligible set can cause: an allocation is
     * history and is not rewritten, so the shortfall is reported rather than hidden.
     */
    public long freeMinor() {
      return Math.subtractExact(eligibleMinor, allocatedMinor);
    }
  }

  /**
   * Every currency an eligible account holds or a goal is set in, by currency code. A currency
   * nothing names is absent.
   *
   * @param netByAccount each account's records summed by currency, as {@link
   *     RecordEntity#netByAccountForUser} returns it
   * @param envelopes what each goal's envelope holds, by goal id; a goal with none is absent
   */
  public static Map<String, Position> calculate(
      List<AccountEntity> accounts,
      Map<UUID, Map<String, Long>> netByAccount,
      List<GoalEntity> goals,
      Map<UUID, Long> envelopes) {
    Map<String, Long> eligible = new TreeMap<>();
    Map<String, List<UUID>> sources = new TreeMap<>();
    Map<String, Long> allocated = new TreeMap<>();

    // Name order, then id, so the list of contributing accounts is the same on every call.
    List<AccountEntity> ordered = new ArrayList<>(accounts);
    ordered.sort(Comparator.comparing((AccountEntity a) -> a.name).thenComparing(a -> a.id));
    for (AccountEntity account : ordered) {
      if (!account.fundsGoals()) {
        continue;
      }
      Map<String, Long> net = netByAccount.getOrDefault(account.id, Map.of());
      for (AccountBalance balance : account.balances) {
        long current = Math.addExact(balance.amountMinor, net.getOrDefault(balance.currency, 0L));
        eligible.merge(balance.currency, current, Math::addExact);
        sources.computeIfAbsent(balance.currency, c -> new ArrayList<>()).add(account.id);
      }
    }
    for (GoalEntity goal : goals) {
      allocated.merge(goal.currency, envelopes.getOrDefault(goal.id, 0L), Math::addExact);
    }

    Map<String, Position> positions = new TreeMap<>();
    for (String currency : eligible.keySet()) {
      positions.put(currency, position(currency, eligible, sources, allocated));
    }
    for (String currency : allocated.keySet()) {
      positions.computeIfAbsent(currency, c -> position(c, eligible, sources, allocated));
    }
    return positions;
  }

  private static Position position(
      String currency,
      Map<String, Long> eligible,
      Map<String, List<UUID>> sources,
      Map<String, Long> allocated) {
    return new Position(
        currency,
        eligible.getOrDefault(currency, 0L),
        allocated.getOrDefault(currency, 0L),
        List.copyOf(sources.getOrDefault(currency, List.of())));
  }

  /** The caller's position in every currency it has one in. */
  public static Map<String, Position> forUser(UUID userId) {
    return calculate(
        AccountEntity.listOwnedBy(userId),
        RecordEntity.netByAccountForUser(userId),
        GoalEntity.listOwnedBy(userId, null),
        GoalAllocationEntity.balances(userId));
  }

  /**
   * The caller's position in one currency — all zero, with no accounts, when nothing names it, so a
   * caller testing an allocation against it needs no special case for "no eligible account".
   */
  public static Position positionIn(UUID userId, String currency) {
    Position position = forUser(userId).get(currency);
    return position != null ? position : new Position(currency, 0L, 0L, List.of());
  }
}
