package prudent.error;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import java.sql.SQLException;

/** Test-only routes that fail in the ways a real handler can. Not part of the shipped server. */
@Path("/test-support/failures")
@PermitAll
@Produces({MediaType.APPLICATION_JSON, "application/x-protobuf"})
public class FailureProbeResource {

  @GET
  @Path("/database")
  public String database() throws SQLException {
    throw new SQLException(
        "ERROR: null value violates not-null constraint\n  Detail: Failing row contains (12345.67, Salary).",
        "23502");
  }

  @GET
  @Path("/web-server-error")
  public String webServerError() {
    throw new WebApplicationException("secret 12345.67", 502);
  }

  @GET
  @Path("/web-client-error")
  public String webClientError() {
    throw new WebApplicationException("teapot", 418);
  }
}
