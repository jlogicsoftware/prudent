import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart' as transport;

/// The value of an import request's [result], or its error thrown, with one change: a response the
/// transport could not decode is thrown WITHOUT the transport's message.
///
/// That message ends with the decoder's own text (`Failed to decode response body: $e`), and a JSON
/// decoder quotes the stretch of the body it choked on. For an import that body is the session's rows,
/// which are lines of the user's bank statement, and a screen's load-error view logs whatever error it
/// is given. So the text is replaced here, once, by a fixed sentence; the error's type and wire code
/// are kept, which is all a log needs.
T unwrapImportResult<T>(ZenResult<T> result) =>
    result.fold((value) => value, (error) => throw withoutDecoderText(error));

/// [error], or a copy that carries no decoder text when it is a decode failure.
ZenError withoutDecoderText(ZenError error) {
  if (error is transport.ZenTransportError &&
      error.zenError.code == transport.ZenTransportErrorCode.decode.wire) {
    return transport.ZenTransportError(
      transport.ZenError(
        code: transport.ZenTransportErrorCode.decode.wire,
        message: 'The response could not be decoded.',
      ),
    );
  }
  return error;
}
