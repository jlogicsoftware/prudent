// The shared package reads a failure's code from `ZenError.internalData` and names the two codes the
// transport makes up itself, because it may not import the transport (ADR-108). This is the test
// that fails when the transport's values and the package's copies part.
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/failure_code.dart';
import 'package:zen_transport/zen_transport.dart';

void main() {
  test('the package names the transport\'s own codes exactly', () {
    expect(FailureCodes.network, ZenTransportErrorCode.network.wire);
    expect(FailureCodes.decode, ZenTransportErrorCode.decode.wire);
  });

  test('a transport error\'s wire code is the one the package reads', () {
    final failure = ZenTransportError(
      ZenError(code: 'conflict', message: 'taken'),
    );
    expect(failureCode(failure), 'conflict');
    expect(
      failureCode(
        ZenTransportError(
          ZenError(code: ZenTransportErrorCode.network.wire, message: 'x'),
        ),
      ),
      FailureCodes.network,
    );
  });
}
