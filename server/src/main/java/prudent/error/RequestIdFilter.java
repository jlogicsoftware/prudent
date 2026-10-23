package prudent.error;

import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;
import java.io.IOException;

/**
 * Gives every request an id and puts it on the response, success or failure.
 *
 * <p>On every response and not only on errors, so a client that logs the header for a request that
 * <em>looked</em> fine can still quote it later when the server's log says otherwise.
 */
@Provider
public class RequestIdFilter implements ContainerRequestFilter, ContainerResponseFilter {

  @Inject RequestId requestId;

  @Override
  public void filter(ContainerRequestContext request) {
    requestId.adopt(request.getHeaderString(RequestId.HEADER));
  }

  @Override
  public void filter(ContainerRequestContext request, ContainerResponseContext response)
      throws IOException {
    response.getHeaders().putSingle(RequestId.HEADER, requestId.value());
  }
}
