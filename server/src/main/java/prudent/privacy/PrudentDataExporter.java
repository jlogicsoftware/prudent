package prudent.privacy;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import prudent.account.AccountEntity;
import prudent.account.AccountMapper;
import prudent.budget.BudgetCarryResetEntity;
import prudent.budget.BudgetEntity;
import prudent.budget.BudgetMapper;
import prudent.category.CategoryEntity;
import prudent.category.CategoryMapper;
import prudent.goal.GoalAllocationEntity;
import prudent.goal.GoalAllocationMapper;
import prudent.goal.GoalEntity;
import prudent.goal.GoalMapper;
import prudent.plan.OccurrenceMapper;
import prudent.plan.PlanClock;
import prudent.plan.PlanEntity;
import prudent.plan.PlanMapper;
import prudent.plan.PlanOccurrenceEntity;
import prudent.proto.v1.DataExport;
import prudent.proto.v1.ExportProfile;
import prudent.record.RecordEntity;
import prudent.record.RecordMapper;
import prudent.settings.SettingsEntity;
import prudent.settings.SettingsMapper;
import zen.identity.user.User;

/**
 * Assembles one {@link DataExport}: everything Prudent stores for a user, in the wire shapes the
 * rest of the API already speaks.
 *
 * <p><strong>It reuses the resources' mappers instead of writing a second set.</strong> A second
 * spelling of a record or an account in an export is a second shape someone has to keep equal to
 * the first, and the export would be the one nobody notices drifting. What it does <em>not</em>
 * reuse is the resources' list queries, which several narrow by lifecycle state or period: an
 * export that inherited "active goals only" would silently be "my data minus what the screens
 * show". Each list below is therefore every row the user owns, read through the entity's
 * unfiltered finder.
 *
 * <p><strong>Completeness is asserted, not hoped for.</strong> {@code PrivacyCoverageTest} seeds
 * every table that carries a {@code user_id}, found from the database's own schema, and fails when
 * one of them does not come back out of here.
 */
@ApplicationScoped
public class PrudentDataExporter {

  /** The layout version of {@link DataExport}; see the field's comment in {@code privacy.proto}. */
  static final int FORMAT_VERSION = 1;

  @Inject AccountMapper accounts;
  @Inject CategoryMapper categories;
  @Inject RecordMapper records;
  @Inject PlanMapper plans;
  @Inject OccurrenceMapper occurrences;
  @Inject BudgetMapper budgets;
  @Inject GoalMapper goals;
  @Inject GoalAllocationMapper allocations;
  @Inject SettingsMapper settings;
  @Inject PlanClock planClock;
  @Inject Clock clock;

  /**
   * Reads everything {@code userId} owns.
   *
   * @param userId the person whose data this is
   * @return the document, with an empty list for anything the user has none of
   */
  @Transactional
  public DataExport export(UUID userId) {
    DataExport.Builder export =
        DataExport.newBuilder()
            .setFormatVersion(FORMAT_VERSION)
            .setExportedAtMs(clock.millis());

    User user = User.findById(userId);
    if (user != null) {
      ExportProfile.Builder profile =
          ExportProfile.newBuilder()
              .setEmail(user.email)
              .setDisplayName(nullToEmpty(user.displayName))
              .setNickname(nullToEmpty(user.nickname))
              .setLanguage(nullToEmpty(user.language));
      if (user.createdAt != null) {
        profile.setCreatedAtMs(user.createdAt.toInstant().toEpochMilli());
      }
      export.setProfile(profile);
    }

    SettingsEntity stored = SettingsEntity.findOwned(userId);
    if (stored != null) {
      export.setSettings(settings.toProto(stored));
    }

    export.addAllAccounts(
        accounts
            .toListResponse(
                AccountEntity.listOwnedBy(userId), RecordEntity.netByAccountForUser(userId))
            .getAccountsList());
    CategoryEntity.listOwnedBy(userId).forEach(c -> export.addCategories(categories.toProto(c)));
    RecordEntity.listOwnedBy(userId).forEach(r -> export.addRecords(records.toProto(r)));

    for (PlanEntity plan : PlanEntity.listOwnedBy(userId)) {
      export.addPlans(plans.toProto(plan));
      // An occurrence's status is reckoned as of its plan's own today, as everywhere else.
      LocalDate today = plan.rule().today(planClock.now());
      for (PlanOccurrenceEntity occurrence : PlanOccurrenceEntity.listForPlan(userId, plan.id)) {
        export.addOccurrences(occurrences.toProto(occurrence, plan, today));
      }
    }

    BudgetEntity.listOwnedBy(userId, null, null).forEach(b -> export.addBudgets(budgets.toProto(b)));
    // Every reset, revoked ones included: the history is never deleted, only marked.
    List<BudgetCarryResetEntity> resets =
        new ArrayList<>(
            BudgetCarryResetEntity.<BudgetCarryResetEntity>list(
                "userId = ?1 order by createdAt, id", userId));
    resets.forEach(r -> export.addCarryOverResets(budgets.toProto(r)));

    GoalEntity.listOwnedBy(userId, null).forEach(g -> export.addGoals(goals.toProto(g)));
    GoalAllocationEntity.history(userId, null)
        .forEach(a -> export.addGoalAllocations(allocations.toProto(a)));

    return export.build();
  }

  private static String nullToEmpty(String value) {
    return value == null ? "" : value;
  }
}
