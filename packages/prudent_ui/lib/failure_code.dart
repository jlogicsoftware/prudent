import 'package:zen_core/zen_core.dart';

/// The machine-readable code a repository failure carries, or null when it carries none.
///
/// A [PrudentRepository] answers a refusal with a [ZenError]; the server implementation's error also
/// holds the wire code (`invalid`, `conflict`, `not_found`, ...) in `internalData['code']`, which is
/// how a screen picks a sentence without importing the transport. Reading it here, from the
/// `zen_core` type, is what keeps this package free of `zen_transport`: any other implementation
/// reports the same codes the same way, by putting them in `internalData`.
String? failureCode(Object error) {
  if (error is! ZenError) return null;
  final Object? code = error.internalData?['code'];
  return code is String ? code : null;
}

/// The codes the transport attaches itself, when a request never reached a server answer. They are
/// the values of `ZenTransportErrorCode.wire`; `client/test/failure_code_test.dart` fails when one
/// of them drifts.
abstract final class FailureCodes {
  /// The request failed before a response was received (connection, DNS, timeout).
  static const String network = 'network_error';

  /// A response body could not be decoded.
  static const String decode = 'decode_error';
}
