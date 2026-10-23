package prudent.error;

import io.quarkus.logging.Log;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.container.ResourceInfo;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.Request;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import java.lang.reflect.Method;
import zen.proto.v1.ZenError;

/**
 * Catches what no other mapper claimed, records it with enough to diagnose and answers with the
 * fixed {@code ZenError} every client already expects.
 *
 * <p><strong>Why Prudent has its own rather than inheriting jZen's.</strong> The framework's
 * catch-all gives the caller the right answer but logs the whole exception, whose messages can
 * quote a database row (see {@link ServerFailureReport}), and logs nothing that ties the line to a
 * request. This one answers identically and writes a line a person can search by the response's
 * {@code X-Request-ID}. It wins over the framework's because that one is registered at the lowest
 * priority on purpose, so that an application's own wins the tie.
 *
 * <p>A {@link WebApplicationException} keeps its own response, as in the framework: it already
 * carries the right status. It is logged only when that status is a server error.
 */
@Provider
public class UnhandledExceptionMapper implements ExceptionMapper<Throwable> {

  /** The code the client sees; fixed, since an unmapped failure is not yet known to be safe to describe. */
  public static final String INTERNAL_ERROR = "internal_error";

  @Inject RequestId requestId;

  @Context ResourceInfo resourceInfo;

  @Context Request request;

  @Override
  public Response toResponse(Throwable exception) {
    if (exception instanceof WebApplicationException wae && wae.getResponse() != null) {
      Response response = wae.getResponse();
      if (response.getStatus() >= 500) {
        report(response.getStatus(), exception);
      }
      return response;
    }
    report(500, exception);
    ZenError error =
        ZenError.newBuilder()
            .setCode(INTERNAL_ERROR)
            .setMessage("Something went wrong. Please try again.")
            .build();
    return Response.status(Response.Status.INTERNAL_SERVER_ERROR).entity(error).build();
  }

  private void report(int status, Throwable exception) {
    Log.error(
        ServerFailureReport.describe(
            requestId.value(), request.getMethod(), handler(), status, exception));
  }

  /** {@code Class.method} of the matched resource, or {@code unmatched} when routing failed. */
  private String handler() {
    Method method = resourceInfo == null ? null : resourceInfo.getResourceMethod();
    return method == null
        ? "unmatched"
        : method.getDeclaringClass().getSimpleName() + "." + method.getName();
  }
}
