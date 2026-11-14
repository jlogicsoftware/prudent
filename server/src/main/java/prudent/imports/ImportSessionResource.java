package prudent.imports;

import io.quarkus.security.Authenticated;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import prudent.CurrentUser;
import prudent.Ids;
import prudent.error.PrudentException;
import prudent.proto.v1.CommitImportSessionRequest;
import prudent.proto.v1.CreateImportSessionRequest;
import prudent.proto.v1.PreviewImportSessionRequest;
import zen.core.http.ZenStatus;

/**
 * Statement import sessions: {@code /api/v1/import-sessions} (M6, jlogicsoftware/prudent#72,
 * ADR-089).
 *
 * <p>A thin shell over {@link ImportWorkflow}, which owns every rule about which phase may happen
 * when. <strong>No route here accepts or returns the uploaded statement after the parse request:
 * </strong> the bytes of {@code POST /api/v1/import-sessions} are handed to the importer and dropped.
 *
 * <p>The resource shape is set out on {@link prudent.category.CategoryResource}.
 */
@Path("/api/v1/import-sessions")
@Authenticated
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
@Consumes({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class ImportSessionResource {

  /** The most sessions one list request returns; a user's ended sessions are kept until erasure. */
  static final int MAX_LIST_LIMIT = 100;

  @Inject CurrentUser currentUser;
  @Inject ImportWorkflow workflow;
  @Inject ImportMapper mapper;

  @GET
  @Operation(
      summary = "List the authenticated user's import sessions",
      description =
          "Newest first, optionally narrowed by state, at most limit sessions (default 50, at most"
              + " 100). Rows are not included; read one session for them.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ListImportSessionsResponse")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description = "A state that is not a session state, or a limit outside 1 to 100",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response list(
      @Parameter(
              description =
                  "Only sessions in this state: PARSED, PREVIEWED, COMMITTED, DISCARDED or EXPIRED."
                      + " Omit for all states.")
          @QueryParam("state")
          String state,
      @Parameter(description = "How many of the newest sessions to return, 1 to 100.")
          @QueryParam("limit")
          @DefaultValue("50")
          int limit) {
    ImportState parsed = state == null || state.isBlank() ? null : parseState(state);
    if (limit < 1 || limit > MAX_LIST_LIMIT) {
      throw PrudentException.invalid("Limit must be between 1 and " + MAX_LIST_LIMIT + ".");
    }
    return Response.ok(
            mapper.toListResponse(
                ImportSessionEntity.listRecent(currentUser.id(), parsed, limit)))
        .build();
  }

  @GET
  @Path("/{id}")
  @Operation(
      summary = "Read one import session with its held rows",
      description =
          "The rows are included while the session is PARSED or PREVIEWED. A session whose time has"
              + " run out is expired by this read.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ImportSession")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      description = "No such session for this user",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response get(@PathParam("id") String id) {
    return view(workflow.get(currentUser.id(), Ids.parse("import session", id)));
  }

  @POST
  @Operation(
      summary = "Parse a statement and open an import session (the parse phase)",
      description =
          "Runs the importer named by formatId over content. Nothing is written unless it accepts the"
              + " statement; then one PARSED session and its rows are. The content is never"
              + " stored.")
  @RequestBody(content = @Content(schema = @Schema(ref = "CreateImportSessionRequest")))
  @APIResponse(
      responseCode = ZenStatus.CREATED,
      content = @Content(schema = @Schema(ref = "ImportSession")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "An unknown format, an empty, oversized or too long statement, an account that is not the"
              + " caller's, inactive, lacks the statement's currency or is not the account the"
              + " statement is for, or a statement the importer rejects (the message names a rule"
              + " and a row number, never content)",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The caller already has the most open import sessions allowed",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response create(CreateImportSessionRequest request) {
    UUID accountId =
        request.hasAccountId() ? Ids.parseInBody("account", request.getAccountId()) : null;
    ImportWorkflow.SessionView created =
        workflow.create(
            currentUser.id(), request.getFormatId(), request.getContent().toByteArray(), accountId);
    return Response.status(Response.Status.CREATED)
        .entity(mapper.toProto(created.session(), created.rows()))
        .build();
  }

  @POST
  @Path("/{id}/preview")
  @Operation(
      summary = "Classify the rows and fix the destination account (the preview phase)",
      description =
          "PARSED or PREVIEWED → PREVIEWED. Omitting accountId keeps the one already chosen. The"
              + " destination is validated on every call (the caller's, active, holds the session's"
              + " currency, is the account the statement is for), so previewing again with another"
              + " account is how to change it without uploading the statement again.")
  @RequestBody(content = @Content(schema = @Schema(ref = "PreviewImportSessionRequest")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ImportSession")))
  @APIResponse(
      responseCode = ZenStatus.BAD_REQUEST,
      description =
          "An account that is not the caller's, is inactive, lacks the session's currency or is not"
              + " the account the statement is for",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The session is not PARSED or PREVIEWED, or has expired",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response preview(@PathParam("id") String id, PreviewImportSessionRequest request) {
    UUID accountId =
        request.hasAccountId() ? Ids.parseInBody("account", request.getAccountId()) : null;
    return view(workflow.preview(currentUser.id(), Ids.parse("import session", id), accountId));
  }

  @POST
  @Path("/{id}/commit")
  @Operation(
      summary = "Write the confirmed session to the ledger (the commit phase)",
      description =
          "PREVIEWED → COMMITTED. Needs a destination account and confirmedAcceptedRows equal to the"
              + " session's accepted rows. Answers 503 until the ledger writer exists"
              + " (jlogicsoftware/prudent#76); the session then stays PREVIEWED.")
  @RequestBody(content = @Content(schema = @Schema(ref = "CommitImportSessionRequest")))
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ImportSession")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description =
          "The session is not PREVIEWED, has expired, has no destination account, has no accepted"
              + " rows, the destination account no longer passes its checks, or the confirmed count"
              + " differs from its accepted rows",
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.SERVICE_UNAVAILABLE,
      description = "Importing into the ledger is not available yet",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response commit(@PathParam("id") String id, CommitImportSessionRequest request) {
    return view(
        workflow.commit(
            currentUser.id(),
            Ids.parse("import session", id),
            request.getConfirmedAcceptedRows()));
  }

  @POST
  @Path("/{id}/discard")
  @Operation(
      summary = "Throw an import session away",
      description = "Allowed while the session is PARSED or PREVIEWED. Deletes its rows.")
  @APIResponse(
      responseCode = ZenStatus.OK,
      content = @Content(schema = @Schema(ref = "ImportSession")))
  @APIResponse(
      responseCode = ZenStatus.NOT_FOUND,
      content = @Content(schema = @Schema(ref = "ZenError")))
  @APIResponse(
      responseCode = ZenStatus.CONFLICT,
      description = "The session has already ended",
      content = @Content(schema = @Schema(ref = "ZenError")))
  public Response discard(@PathParam("id") String id) {
    return view(workflow.discard(currentUser.id(), Ids.parse("import session", id)));
  }

  private Response view(ImportWorkflow.SessionView view) {
    return Response.ok(mapper.toProto(view.session(), view.rows())).build();
  }

  private static ImportState parseState(String name) {
    try {
      return ImportState.valueOf(name);
    } catch (IllegalArgumentException unknown) {
      throw PrudentException.invalid(
          "State must be PARSED, PREVIEWED, COMMITTED, DISCARDED or EXPIRED.");
    }
  }
}
