import 'package:zen_core/zen_core.dart';

import '../failure_code.dart';

/// The value of an import request's [result], or its error thrown, with one change: a response the
/// transport could not decode is thrown as an [ImportDecodeFailure], which carries none of the
/// transport's message.
///
/// That message ends with the decoder's own text (`Failed to decode response body: $e`), and a JSON
/// decoder quotes the stretch of the body it choked on. For an import that body is the session's rows,
/// which are lines of the user's bank statement, and a screen's load-error view logs whatever error it
/// is given. So the text is replaced here, once, by a fixed sentence; the wire code is kept, which is
/// all a log needs. The repository's own answer is not touched, so this is the one place that
/// guarantees it, for any repository.
T unwrapImportResult<T>(ZenResult<T> result) =>
    result.fold((value) => value, (error) => throw withoutDecoderText(error));

/// [error], or an [ImportDecodeFailure] when it is a decode failure.
ZenError withoutDecoderText(ZenError error) =>
    failureCode(error) == FailureCodes.decode ? const ImportDecodeFailure() : error;

/// A response that could not be decoded, with no text of the response in it.
class ImportDecodeFailure extends ZenError {
  const ImportDecodeFailure()
    : super(
        'The response could not be decoded.',
        internalData: const {'code': FailureCodes.decode},
      );
}
