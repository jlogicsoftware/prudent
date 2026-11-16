import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_ui/failure_code.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  test('reads the wire code a repository failure carries', () {
    const failure = ZenConflictError('taken', internalData: {'code': 'conflict'});
    expect(failureCode(failure), 'conflict');
  });

  test('a failure with no code, or a code that is not text, has none', () {
    expect(failureCode(const ZenUnknownError('boom')), isNull);
    expect(failureCode(const ZenUnknownError('boom', internalData: {'code': 7})), isNull);
    expect(failureCode(const ZenUnknownError('boom', internalData: {'other': 'x'})), isNull);
  });

  test('something that is not a ZenError has none', () {
    expect(failureCode(StateError('not a repository failure')), isNull);
    expect(failureCode('conflict'), isNull);
  });
}
