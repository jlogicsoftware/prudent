package prudent.proto;

import io.quarkus.runtime.annotations.RegisterForReflection;
import prudent.proto.v1.Account;
import prudent.proto.v1.Budget;
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.BudgetSummaryResponse;
import prudent.proto.v1.Category;
import prudent.proto.v1.CategoryBudgetSummary;
import prudent.proto.v1.CategorySpend;
import prudent.proto.v1.ConfirmOccurrenceRequest;
import prudent.proto.v1.ConfirmOccurrenceResponse;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CreateCategoryRequest;
import prudent.proto.v1.CreateCorrectionRequest;
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.CreateGoalRequest;
import prudent.proto.v1.CreatePlanRequest;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.CreateTransferRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.CurrencyFreeMoney;
import prudent.proto.v1.DueReminder;
import prudent.proto.v1.GetFreeMoneyResponse;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalAllocation;
import prudent.proto.v1.GoalEnvelope;
import prudent.proto.v1.GoalProgress;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.ListBudgetCarryOverResetsResponse;
import prudent.proto.v1.ListBudgetsResponse;
import prudent.proto.v1.ListCategoriesResponse;
import prudent.proto.v1.ListGoalAllocationsResponse;
import prudent.proto.v1.ListGoalEnvelopesResponse;
import prudent.proto.v1.ListGoalProgressResponse;
import prudent.proto.v1.ListGoalsResponse;
import prudent.proto.v1.ListOccurrencesResponse;
import prudent.proto.v1.ListPlansResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.ListRemindersResponse;
import prudent.proto.v1.PeriodSpend;
import prudent.proto.v1.Plan;
import prudent.proto.v1.PlanOccurrence;
import prudent.proto.v1.Record;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.Reminder;
import prudent.proto.v1.ResetBudgetCarryOverRequest;
import prudent.proto.v1.SetBudgetRequest;
import prudent.proto.v1.Settings;
import prudent.proto.v1.SpendByCategoryResponse;
import prudent.proto.v1.SpendByPeriodResponse;
import prudent.proto.v1.Transfer;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.proto.v1.UpdateCategoryRequest;
import prudent.proto.v1.UpdateGoalRequest;
import prudent.proto.v1.UpdatePlanRequest;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.proto.v1.UpdateSettingsRequest;

/**
 * Makes every generated Prudent protobuf message reflectively reachable in a native image.
 *
 * <p><b>Why this is needed.</b> The canonical proto3 JSON path — {@code JsonFormat}, used by jZen's
 * {@code ProtoJsonMessageBodyWriter} — resolves field accessors <em>reflectively</em>. A native
 * image strips methods nothing reaches statically, so the first JSON response that carries a
 * message of ours fails with {@code NoSuchMethodException:
 * prudent.proto.v1.Settings.getMainCurrency()} and the client sees a 500. The binary path uses
 * generated code instead, so it keeps working, which is how a deployed service can answer
 * {@code /health} and every rejection correctly while every authenticated screen is broken.
 *
 * <p><b>Why jZen's own registration does not cover this.</b> {@code zen.transport.ZenProtoReflection}
 * lists jZen's messages ({@code zen.proto.v1.*}); the messages in {@code proto/prudent/v1} are
 * Prudent's and are the product surface. Quarkus does not infer them either: resources return
 * {@code Response} with an {@code @APIResponse} schema reference, so no message type appears in a
 * signature for static analysis to find.
 *
 * <p><b>The list is checked, not trusted.</b> {@code task verify:reflection} fails when a message
 * declared in {@code proto/prudent/v1/*.proto} is missing below, or one named below no longer
 * exists, so a message added to a proto file cannot reach a native build unregistered. Nested
 * {@code Builder} types are covered because {@code ignoreNested} defaults to false.
 *
 * <p>This class is never instantiated. It exists only to carry the annotation.
 */
@RegisterForReflection(
    targets = {
      Account.class,
      Budget.class,
      BudgetCarryOverReset.class,
      BudgetSummaryResponse.class,
      Category.class,
      CategoryBudgetSummary.class,
      CategorySpend.class,
      ConfirmOccurrenceRequest.class,
      ConfirmOccurrenceResponse.class,
      CreateAccountRequest.class,
      CreateCategoryRequest.class,
      CreateCorrectionRequest.class,
      CreateGoalAllocationRequest.class,
      CreateGoalRequest.class,
      CreatePlanRequest.class,
      CreateRecordRequest.class,
      CreateTransferRequest.class,
      CurrencyBalance.class,
      CurrencyFreeMoney.class,
      DueReminder.class,
      GetFreeMoneyResponse.class,
      Goal.class,
      GoalAllocation.class,
      GoalEnvelope.class,
      GoalProgress.class,
      ListAccountsResponse.class,
      ListBudgetCarryOverResetsResponse.class,
      ListBudgetsResponse.class,
      ListCategoriesResponse.class,
      ListGoalAllocationsResponse.class,
      ListGoalEnvelopesResponse.class,
      ListGoalProgressResponse.class,
      ListGoalsResponse.class,
      ListOccurrencesResponse.class,
      ListPlansResponse.class,
      ListRecordsResponse.class,
      ListRemindersResponse.class,
      PeriodSpend.class,
      Plan.class,
      PlanOccurrence.class,
      Record.class,
      Recurrence.class,
      Reminder.class,
      ResetBudgetCarryOverRequest.class,
      SetBudgetRequest.class,
      Settings.class,
      SpendByCategoryResponse.class,
      SpendByPeriodResponse.class,
      Transfer.class,
      UpdateAccountRequest.class,
      UpdateCategoryRequest.class,
      UpdateGoalRequest.class,
      UpdatePlanRequest.class,
      UpdateRecordRequest.class,
      UpdateSettingsRequest.class,
    })
public final class PrudentProtoReflection {

  private PrudentProtoReflection() {}
}
