package prudent.goal;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeSet;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.CreateGoalAllocationRequest;
import prudent.proto.v1.GoalAllocationKind;
import zen.core.http.ZenStatus;

/**
 * Goal envelopes and their history: {@code /api/v1/goal-allocations} (M4,
 * jlogicsoftware/prudent#64, ADR-050).
 *
 * <p>Money is set aside for a goal ({@code ALLOCATE}), released from it ({@code WITHDRAW}) or
 * reassigned to another goal in the same currency ({@code MOVE}). Each action is one entry in an
 * <strong>append-only history</strong>: there is no update and no DELETE, so a mistake is
 * corrected by another entry. An envelope has no stored amount — it is calculated from the entries
 * on every read — and nothing here touches an account balance, a record or an analytics total.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/goal-allocations")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class GoalAllocationResource {

  /** Matches the schema's {@code char_length(note) <= 500}, which counts characters. */
  static final int MAX_NOTE_LENGTH = 500;

  @Inject CurrentUser currentUser;
  @Inject GoalAllocationMapper mapper;

  @GET
  @Operation(
      summary = "The authenticated user's envelope history",
      description =
          "Every entry, newest first. Optionally narrowed by goalId (UUID) to the entries that put"
              + " money into or took it out of that goal.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListGoalAllocationsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A malformed goalId",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response history(@QueryParam("goalId") String goalId) {
    UUID parsed = goalId == null || goalId.isBlank() ? null : Ids.parseInBody("goal", goalId);
    return Response.ok(
            mapper.toListResponse(GoalAllocationEntity.history(currentUser.id(), parsed)))
        .build();
  }

  @GET
  @Path("/envelopes")
  @Operation(
      summary = "What each goal's envelope holds",
      description =
          "One envelope per goal, in the goals' creation order, a goal with no entries included at"
              + " zero. Calculated from the history on every call. This is virtual money set aside:"
              + " it is not part of any account balance.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListGoalEnvelopesResponse")))
  public Response envelopes() {
    UUID userId = currentUser.id();
    return Response.ok(
            mapper.toEnvelopesResponse(
                GoalEntity.listOwnedBy(userId, null), GoalAllocationEntity.balances(userId)))
        .build();
  }

  @GET
  @Path("/free-money")
  @Operation(
      summary = "What the user may still set aside for goals, per currency",
      description =
          "Per currency: the eligible money (the current balances of the active accounts marked"
              + " eligibleForGoals), what the envelopes already hold, and the difference, which is"
              + " negative when the envelopes hold more than the eligible accounts do. Calculated"
              + " on every call and never blended across currencies.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "GetFreeMoneyResponse")))
  public Response freeMoney() {
    return Response.ok(mapper.toFreeMoneyResponse(FreeMoney.forUser(currentUser.id()))).build();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Read one history entry")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "GoalAllocation")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such entry for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    GoalAllocationEntity entry =
        GoalAllocationEntity.findOwned(currentUser.id(), Ids.parse("goal allocation", id));
    if (entry == null) {
      throw PrudentException.notFound("goal allocation", id);
    }
    return Response.ok(mapper.toProto(entry)).build();
  }

  @POST
  @Transactional
  @Operation(
      summary = "Allocate, withdraw or move money between goal envelopes",
      description =
          "ALLOCATE needs targetGoalId, WITHDRAW needs sourceGoalId and MOVE needs both, in the"
              + " same currency. The entry is added to an append-only history; nothing already"
              + " written is changed. No account balance moves. An ALLOCATE may not be more than"
              + " the currency's free money (GET /free-money).")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateGoalAllocationRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "GoalAllocation")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "An unknown kind, an amount that is not positive, a goal id the kind does not use or"
              + " lacks, a malformed goal id, a move to the same goal or between currencies, a"
              + " note longer than 500 characters, or an envelope that would exceed what an"
              + " amount can hold",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such goal for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description =
          "The envelope does not hold the amount, an allocation is more than the currency's free"
              + " money, or a goal's state does not allow the entry (money goes into an active"
              + " goal, comes out of an active or completed one)",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateGoalAllocationRequest request) {
    UUID userId = currentUser.id();
    AllocationKind kind = parseKind(request.getKind());
    long amount = request.getAmountMinor();
    // Positive, not merely nonzero: the direction is the kind. Zero is also what an omitted field
    // decodes to, so refusing it keeps a body that forgot the amount from becoming an entry that
    // moved nothing.
    if (amount <= 0) {
      throw PrudentException.invalid("An envelope entry needs a positive amount.");
    }
    String note = request.getNote().strip();
    if (note.codePointCount(0, note.length()) > MAX_NOTE_LENGTH) {
      throw PrudentException.invalid("A note may be at most " + MAX_NOTE_LENGTH + " characters.");
    }
    UUID sourceId =
        goalIdFor(
            kind.hasSource(), "source", request.hasSourceGoalId(), request.getSourceGoalId(), kind);
    UUID targetId =
        goalIdFor(
            kind.hasTarget(), "target", request.hasTargetGoalId(), request.getTargetGoalId(), kind);
    if (sourceId != null && sourceId.equals(targetId)) {
      throw PrudentException.invalid("Money cannot be moved to the goal it already is in.");
    }

    if (kind == AllocationKind.ALLOCATE) {
      // The cap reads every envelope in the currency, so this entry waits for any other allocation
      // in it. The goal is read first only to learn the currency; the lock below is what protects
      // the figures, and a goal that is not the caller's is refused here exactly as it would be
      // by lockGoals.
      String currency = GoalEntity.currencyOfOwned(userId, targetId);
      if (currency == null) {
        throw PrudentException.notFound("goal", targetId);
      }
      GoalEntity.lockOwnedIn(userId, currency);
    }
    Map<UUID, GoalEntity> goals = lockGoals(userId, sourceId, targetId);
    GoalEntity source = sourceId == null ? null : goals.get(sourceId);
    GoalEntity target = targetId == null ? null : goals.get(targetId);

    // Never converted (ADR-009): the two halves of a move are in one currency or it is refused.
    if (source != null && target != null && !source.currency.equals(target.currency)) {
      throw PrudentException.invalid(
          "Money cannot be moved between goals in different currencies ("
              + source.currency + " and " + target.currency + ").");
    }
    if (source != null && !source.status.releasesMoney()) {
      throw PrudentException.conflict(
          "This goal is " + source.status + ", so money cannot be taken out of it."
              + " Reactivate it first.");
    }
    if (target != null && !target.status.acceptsMoney()) {
      throw PrudentException.conflict(
          "This goal is " + target.status + ", so money cannot be put into it."
              + (target.status == GoalState.ARCHIVED ? " Reactivate it first." : ""));
    }
    if (source != null && GoalAllocationEntity.balance(userId, source.id) < amount) {
      throw PrudentException.conflict(
          "This goal's envelope holds less than the amount requested.");
    }
    if (target != null) {
      try {
        Math.addExact(GoalAllocationEntity.balance(userId, target.id), amount);
      } catch (ArithmeticException tooLarge) {
        throw PrudentException.invalid("That amount would be more than an envelope can hold.");
      }
    }
    // After the overflow check, so an amount no envelope could hold is a 400 however much money is
    // free, as it was before there was a cap.
    if (kind == AllocationKind.ALLOCATE) {
      FreeMoney.Position position = FreeMoney.positionIn(userId, target.currency);
      if (amount > position.freeMinor()) {
        // Minor units, because the server does not format money: the client owns that (money.dart).
        throw PrudentException.conflict(
            "That is more than the free money in "
                + target.currency
                + " (free: "
                + position.freeMinor()
                + ", requested: "
                + amount
                + ", in minor units). Money is free when it is in an active account marked"
                + " eligible for goals and not already set aside.");
      }
    }

    GoalAllocationEntity entry = new GoalAllocationEntity();
    // Server-minted; the request message has no id field.
    entry.id = UUID.randomUUID();
    entry.userId = userId;
    entry.kind = kind;
    entry.sourceGoalId = sourceId;
    entry.targetGoalId = targetId;
    entry.currency = (source != null ? source : target).currency;
    entry.amountMinor = amount;
    entry.note = note;
    entry.createdAt = Instant.now();
    entry.createdBy = userId;
    entry.persist();
    return Response.status(Response.Status.CREATED).entity(mapper.toProto(entry)).build();
  }

  /**
   * Loads and locks the named goals, in id order so two requests naming the same pair cannot each
   * hold one and wait for the other. Refuses (404) a goal that is not the caller's.
   */
  private static Map<UUID, GoalEntity> lockGoals(UUID userId, UUID... ids) {
    TreeSet<UUID> ordered = new TreeSet<>();
    for (UUID id : ids) {
      if (id != null) {
        ordered.add(id);
      }
    }
    Map<UUID, GoalEntity> goals = new HashMap<>();
    for (UUID id : ordered) {
      GoalEntity goal = GoalEntity.findOwnedForUpdate(userId, id);
      if (goal == null) {
        throw PrudentException.notFound("goal", id);
      }
      goals.put(id, goal);
    }
    return goals;
  }

  /**
   * The goal id a request carries for one side of the entry: required when the kind uses that side
   * and refused when it does not, so a client that mixed up two actions is told rather than
   * guessed at.
   */
  private static UUID goalIdFor(
      boolean used, String side, boolean present, String value, AllocationKind kind) {
    if (!used) {
      if (present) {
        throw PrudentException.invalid("A " + kind + " entry does not take a " + side + " goal.");
      }
      return null;
    }
    if (!present) {
      throw PrudentException.invalid("A " + kind + " entry needs a " + side + " goal.");
    }
    return Ids.parseInBody(side + " goal", value);
  }

  /** The kind the wire names — refused, not guessed, when it names none. */
  static AllocationKind parseKind(GoalAllocationKind wire) {
    return switch (wire) {
      case GOAL_ALLOCATION_KIND_ALLOCATE -> AllocationKind.ALLOCATE;
      case GOAL_ALLOCATION_KIND_WITHDRAW -> AllocationKind.WITHDRAW;
      case GOAL_ALLOCATION_KIND_MOVE -> AllocationKind.MOVE;
      case GOAL_ALLOCATION_KIND_UNSPECIFIED, UNRECOGNIZED ->
          throw PrudentException.invalid(
              "An envelope entry needs a kind: ALLOCATE, WITHDRAW or MOVE.");
    };
  }
}
