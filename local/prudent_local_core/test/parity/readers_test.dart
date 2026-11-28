// What the shared readers refuse: an answer that holds something the scenario cannot name must not
// be observed as one that does not hold it.
import 'package:prudent_local_core/parity.dart';
import 'package:test/test.dart';

void main() {
  group('spend by category', () {
    final bindings = ParityBindings()..bind('food', 'id-food');
    Map<String, Object?> read(List<Map<String, Object?>> items) =>
        ParityReaders.spendByCategory({'currency': 'THB', 'items': items}, bindings);

    test('names every category it was answered', () {
      expect(
        read([
          {'categoryId': 'id-food', 'amountMinor': '12'},
        ]),
        {
          'currency': 'THB',
          'items': {'food': '12'},
        },
      );
      expect(ParityReaders.spendByCategory({'currency': 'THB'}, bindings)['items'], isEmpty);
    });

    test('an extra category nothing bound fails the read, naming it', () {
      expect(
        () => read([
          {'categoryId': 'id-food', 'amountMinor': '12'},
          {'categoryId': 'id-unknown', 'amountMinor': '1'},
        ]),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('id-unknown'))),
      );
    });

    test('an item with no category at all fails the read', () {
      expect(
        () => read([
          {'amountMinor': '1'},
        ]),
        throwsStateError,
      );
    });
  });
}
