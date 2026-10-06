package prudent.plan;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.Currencies;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.error.PrudentException;
import prudent.proto.v1.CreatePlanRequest;
import prudent.proto.v1.Recurrence;
import prudent.proto.v1.UpdatePlanRequest;
import prudent.record.RecordEntity;
import zen.core.http.ZenStatus;

/**
 * Prudent's plans: {@code /api/v1/plans} (M2, jlogicsoftware/prudent#34, ADR-037).
 *
 * <p>A plan is expected income or spending — one-off or recurring — and it is <strong>never a
 * transaction</strong>. Saving, editing or deleting one touches only {@code prudent_plan}; no
 * balance, record or analytics total moves. Turning an occurrence into an actual record is an
 * explicit confirmation (jlogicsoftware/prudent#57), not something this resource does.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/plans")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class PlanResource {

  @Inject CurrentUser currentUser;
  @Inject PlanMapper mapper;
  @Inject OccurrenceGenerator occurrenceGenerator;

  @GET
  @Operation(summary = "List the authenticated user's plans")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListPlansResponse")))
  public Response list() {
    return Response.ok(mapper.toListResponse(PlanEntity.listOwnedBy(currentUser.id()))).build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one plan")
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Plan")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    return Response.ok(mapper.toProto(require(currentUser.id(), id))).build();
  }

  @POST
  @Transactional
  @Operation(summary = "Create a one-off or recurring plan")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreatePlanRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "Plan")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "A blank title, a zero amount, an account or category that is not the caller's, a"
              + " currency the account does not hold, an invalid recurrence, or a reminder lead"
              + " time that is not one of the supported ones",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreatePlanRequest request) {
    UUID userId = currentUser.id();
    PlanEntity entity = new PlanEntity();
    // Server-minted; the request message has no id field.
    entity.id = UUID.randomUUID();
    entity.userId = userId;
    apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getCurrency(),
        request.getAccountId(), request.getCategoryId(),
        request.hasPayee() ? request.getPayee() : null,
        request.hasNote() ? request.getNote() : null,
        request.getRecurrence(), request.hasRecurrence(),
        ReminderSetting.fromProto(request.getReminder(), request.hasReminder()));
    entity.persist();
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entity)).build();
  }

  @PUT
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Replace a plan")
  @RequestBody(content = @Content(schema = @Schema(ref = "UpdatePlanRequest")))
  @APIResponse(responseCode = ZenStatus.OK, content = @Content(schema = @Schema(ref = "Plan")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response replace(@PathParam("id") String id, UpdatePlanRequest request) {
    UUID userId = currentUser.id();
    PlanEntity entity = require(userId, id);
    RecurrenceRule before = entity.rule();
    apply(entity, userId, request.getTitle(), request.getAmountMinor(), request.getCurrency(),
        request.getAccountId(), request.getCategoryId(),
        request.hasPayee() ? request.getPayee() : null,
        request.hasNote() ? request.getNote() : null,
        request.getRecurrence(), request.hasRecurrence(),
        ReminderSetting.fromProto(request.getReminder(), request.hasReminder()));
    if (!before.equals(entity.rule())) {
      // Generation only ever adds (ADR-038), so still-planned occurrences the new rule no longer
      // produces would sit beside its own for good. Completed and skipped ones are the user's
      // decisions and stay (ADR-039); the views regenerate whatever the new rule adds.
      occurrenceGenerator.dropStale(entity);
    }
    return Response.ok(mapper.toProto(entity)).build();
  }

  @DELETE
  @Path("/{id}")
  @Transactional
  @Operation(summary = "Delete a plan")
  @APIResponse(responseCode = ZenStatus.NO_CONTENT, description = "Deleted")
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response delete(@PathParam("id") String id) {
    // A hard delete, and a harmless one: a plan is not money that moved, so removing it changes no
    // balance and no total.
    PlanEntity entity = require(currentUser.id(), id);
    // The transactions this plan produced are the ledger and stay in it. They are cut loose first,
    // because both the occurrences and the plan they name are about to go and neither reference
    // carries an ON DELETE CASCADE. No balance or total moves: only where a record says it came
    // from.
    RecordEntity.detachFromPlan(entity.userId, entity.id);
    // Before the plan: the occurrence reference carries no ON DELETE CASCADE.
    PlanOccurrenceEntity.deleteForPlan(entity.id);
    entity.delete();
    return Response.noContent().build();
  }

  private PlanEntity require(UUID userId, String id) {
    PlanEntity entity = PlanEntity.findOwned(userId, Ids.parse("plan", id));
    if (entity == null) {
      throw PrudentException.notFound("plan", id);
    }
    return entity;
  }

  /**
   * Validates and writes every mutable field. Shared by create and replace, so a rule cannot hold
   * on create and lapse on edit. The account, category and currency rules are {@code
   * RecordResource}'s, deliberately: a plan has to be confirmable into a record later, so anything
   * a record would refuse is refused here at the point the user can still fix it.
   */
  private void apply(
      PlanEntity entity,
      UUID userId,
      String title,
      long amountMinor,
      String currency,
      String accountId,
      String categoryId,
      String payee,
      String note,
      Recurrence recurrence,
      boolean hasRecurrence,
      ReminderSetting reminder) {

    if (title == null || title.isBlank()) {
      throw PrudentException.invalid("A plan needs a title.");
    }
    // Signed as a record is (ADR-014); zero would be a plan to move nothing.
    if (amountMinor == 0) {
      throw PrudentException.invalid(
          "A plan needs a nonzero amount. Negative is planned spending, positive is income.");
    }

    AccountEntity account = AccountEntity.findOwned(userId, parseReference("account", accountId));
    if (account == null) {
      throw PrudentException.invalid("No such account for this user: " + accountId);
    }
    CategoryEntity category =
        CategoryEntity.findOwned(userId, parseReference("category", categoryId));
    if (category == null) {
      throw PrudentException.invalid("No such category for this user: " + categoryId);
    }

    // As for a record (RecordWriter): an archived category takes no NEW plan, but a plan already
    // filed under it can still be edited without changing its category (ADR-047).
    if (!category.id.equals(entity.categoryId)) {
      category.requireActive();
    }

    String normalized = Currencies.normalize(currency);
    if (!Currencies.isValid(normalized)) {
      throw PrudentException.invalid("'" + currency + "' is not an ISO-4217 currency.");
    }
    if (!AccountEntity.holds(account, normalized)) {
      throw PrudentException.invalid(
          "Account '" + account.name + "' does not hold " + normalized
              + ". Add the currency to the account first.");
    }

    RecurrenceRule rule = RecurrenceRule.fromProto(recurrence, hasRecurrence);

    entity.title = title.trim();
    entity.amountMinor = amountMinor;
    entity.currency = normalized;
    entity.accountId = account.id;
    entity.categoryId = category.id;
    entity.payee = blankToNull(payee);
    entity.note = blankToNull(note);
    entity.setRule(rule);
    entity.setReminder(reminder);
  }

  /**
   * A body-field id. The blank case is answered here so the message names a plan; the malformed
   * case is {@link Ids#parseInBody}'s.
   */
  private static UUID parseReference(String what, String id) {
    if (id == null || id.isBlank()) {
      throw PrudentException.invalid("A plan needs its " + what + ".");
    }
    return Ids.parseInBody(what, id);
  }

  private static String blankToNull(String value) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }
}
