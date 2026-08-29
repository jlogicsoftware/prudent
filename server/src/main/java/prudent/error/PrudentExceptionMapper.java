package prudent.error;

import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import zen.proto.v1.ZenError;

/**
 * Renders a {@link PrudentException} as a {@code ZenError} proto body at the exception's status.
 *
 * <p>This is the framework's shared error path, reused rather than re-invented: endpoints return
 * typed proto and errors return the one {@code ZenError} proto, never an ad-hoc envelope.
 * {@code zen-transport}'s writers serialise it in whichever format the caller negotiated and the
 * response filter echoes {@code X-Zen-Transport}, so a client decodes an error with the same codec
 * it would a success. {@code zen-identity}'s {@code AuthExceptionMapper} is the same shape for the
 * framework's own refusals.
 *
 * <p><strong>No explicit media type</strong>, deliberately. The negotiated {@code Accept} header —
 * rewritten by the pre-matching transport filter — selects the matching proto writer, so a
 * protobuf-mode caller gets a protobuf {@code ZenError} and a JSON caller gets proto3 JSON. Naming
 * a type here would pin every error to one format while successes stayed negotiable, and the
 * mismatch would surface as an undecodable error body only in the mode nobody tested.
 */
@Provider
public class PrudentExceptionMapper implements ExceptionMapper<PrudentException> {

  @Override
  public Response toResponse(PrudentException exception) {
    ZenError error =
        ZenError.newBuilder()
            .setCode(exception.code())
            .setMessage(exception.getMessage() != null ? exception.getMessage() : "")
            .build();
    return Response.status(exception.status()).entity(error).build();
  }
}
