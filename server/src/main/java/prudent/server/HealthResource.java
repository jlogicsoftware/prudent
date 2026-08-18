package prudent.server;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import zen.proto.v1.HealthStatus;

/**
 * Liveness/readiness probe. Follows {@code ../jZen/apps/zen_demo/zen_demo_server}'s
 * {@code HealthResource} exactly: the entity is the framework's {@code HealthStatus} (from
 * {@code zen-proto}, already a Prudent dependency), wrapped in {@link Response} rather than
 * returned bare so the transport seam's writers resolve at runtime instead of Quarkus REST's
 * build-time Jackson writer taking it first and 500ing on the proto's builder internals.
 *
 * <p>{@code @PermitAll} is required, not decorative — {@code zen-transport} denies unannotated
 * endpoints by default. This is what {@code task test:e2e} polls before driving the suite, and
 * what a deploy's readiness check and {@code task verify:deploy} both call.
 */
@Path("/api/v1/health")
public class HealthResource {

  @GET
  @Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
  @PermitAll
  @Operation(summary = "Liveness/readiness probe")
  @APIResponse(
      responseCode = PrudentStatus.OK,
      description = "Service is healthy",
      content = {
        @Content(mediaType = MediaType.APPLICATION_JSON, schema = @Schema(ref = "HealthStatus")),
        @Content(mediaType = "application/x-protobuf", schema = @Schema(ref = "HealthStatus"))
      })
  public Response health() {
    HealthStatus status =
        HealthStatus.newBuilder()
            .setStatus("ok")
            .setService("prudent-server")
            .setTimestampMs(System.currentTimeMillis())
            .build();
    return Response.ok(status).build();
  }
}
