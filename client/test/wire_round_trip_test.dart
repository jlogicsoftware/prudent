// Prudent's contract, exercised on the wire.
//
// WHAT THIS SUITE IS FOR. `task sync:contracts` proves the generated code is up to date with the
// .proto files. It cannot prove the result is CORRECT, or that it agrees with itself across the
// two transport modes — and those two modes are genuinely different code paths, not one path with
// a flag: Protobuf binary uses the generated field descriptors, while canonical proto3 JSON goes
// through toProto3Json/mergeFromProto3Json and resolves accessors reflectively. jZen's own history
// records a deployed revision that served Protobuf perfectly and 500'd on every JSON response, so
// "it works" established in one mode says nothing about the other.
//
// Every case therefore runs both modes over the REAL codec (`ZenProtoCodec`, from
// package:zen_transport) rather than a local reimplementation of it, and asserts field-for-field
// equality after the round trip.

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/generated/prudent/v1/settings.pb.dart';
import 'package:protobuf/protobuf.dart';
import 'package:zen_transport/zen_transport.dart';

/// Encodes [message] in [format] and decodes it back into a fresh instance.
///
/// The bytes go through the transport's own codec in both directions, so a mode that cannot
/// represent a value fails here rather than in production.
T roundTrip<T extends GeneratedMessage>(
  T message,
  ZenTransportFormat format,
  T Function() createEmpty,
) => ZenProtoCodec.decode(ZenProtoCodec.encode(message, format), format, createEmpty);

void main() {
  // Both modes, every test. Naming the format in the test description means a failure says which
  // wire format broke without anyone opening the file.
  for (final format in ZenTransportFormat.values) {
    group('${format.value} wire format', () {
      test('a Record survives the round trip field for field', () {
        final original = Record(
          id: '6f9619ff-8b86-d011-b42d-00c04fc964ff',
          title: 'Groceries',
          // 12.34 in minor units.
          amountMinor: Int64(1234),
          currency: 'PLN',
          date: '2026-08-15',
          categoryId: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
          accountId: '018f3a1b-2c4d-7e8f-9a0b-1c2d3e4f5a6b',
        );

        final decoded = roundTrip(original, format, Record.new);

        expect(decoded.id, original.id);
        expect(decoded.title, original.title);
        expect(decoded.amountMinor, original.amountMinor);
        expect(decoded.currency, original.currency);
        expect(decoded.date, original.date);
        expect(decoded.categoryId, original.categoryId);
        expect(decoded.accountId, original.accountId);
        expect(decoded, original);
      });

      test('a multi-currency Account survives the round trip field for field', () {
        final original = Account(
          id: '018f3a1b-2c4d-7e8f-9a0b-1c2d3e4f5a6b',
          name: 'Everyday',
          type: AccountType.ACCOUNT_TYPE_CHECKING,
          isDefault: true,
          // FALSE ON PURPOSE, all three. A false bool is the proto3 default, so these fields are
          // absent from both encodings — and this is the case that proves a full-replacement PUT
          // does what its message says: they must come back false rather than being filled in with
          // whatever the sender "must have meant".
          isActive: false,
          includeInTotal: false,
          includeInOverview: false,
          // Three currencies in ONE account, which is the shape the product asked for. Note the
          // negative entry: one pocket may be overdrawn while another is not, and money is signed.
          balances: [
            CurrencyBalance(currency: 'PLN', amountMinor: Int64(125000)),
            CurrencyBalance(currency: 'EUR', amountMinor: Int64(-2550)),
            CurrencyBalance(currency: 'USD', amountMinor: Int64(0)),
          ],
        );

        final decoded = roundTrip(original, format, Account.new);

        expect(decoded.id, original.id);
        expect(decoded.name, original.name);
        expect(decoded.type, AccountType.ACCOUNT_TYPE_CHECKING);
        expect(decoded.isDefault, isTrue);
        expect(decoded.isActive, isFalse);
        expect(decoded.includeInTotal, isFalse);
        expect(decoded.includeInOverview, isFalse);

        // ORDER IS PART OF THE VALUE. A repeated field is a list, not a set, and the client will
        // render these in the order the server sent them — so a codec that preserved the entries
        // but not their sequence would be a defect the field-count assertion alone would miss.
        expect(decoded.balances.map((b) => b.currency).toList(), ['PLN', 'EUR', 'USD']);
        expect(decoded.balances[0].amountMinor, Int64(125000));
        expect(decoded.balances[1].amountMinor, Int64(-2550));
        // A zero-amount pocket is a real state — an account holds the currency, with none of it in
        // it. amount_minor = 0 is the proto3 default, so it is absent from both encodings; the
        // entry must survive on the strength of its currency alone.
        expect(decoded.balances[2].currency, 'USD');
        expect(decoded.balances[2].amountMinor, Int64.ZERO);
        expect(decoded.balances.length, 3);

        expect(decoded, original);
      });

      test('an empty balance list round-trips as empty, not as absent', () {
        // The server rejects an account with no currencies, but the CONTRACT must still carry the
        // state faithfully — a repeated field with no entries encodes to nothing in both formats,
        // and "decoded to an empty list" and "failed to decode" must not look the same. A
        // validation rule the wire cannot express is one the server has to enforce, which is
        // exactly what accounts.proto says.
        final decoded = roundTrip(Account(name: 'No currencies'), format, Account.new);

        expect(decoded.balances, isEmpty);
      });

      test('a CreateRecordRequest names its currency, and carries no id', () {
        // The half of the multi-currency change that lives on the request side. A record used to
        // inherit its account's currency, and the create message had no currency field at all;
        // an account now holds several, so the record has to say which balance it moved.
        final decoded = roundTrip(
          CreateRecordRequest(
            title: 'Hotel',
            amountMinor: Int64(48000),
            date: '2026-08-16',
            categoryId: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
            accountId: '018f3a1b-2c4d-7e8f-9a0b-1c2d3e4f5a6b',
            currency: 'EUR',
          ),
          format,
          CreateRecordRequest.new,
        );

        expect(decoded.currency, 'EUR');
        expect(decoded.amountMinor, Int64(48000));
        // Identity is the server's. The generated class has no id field to set, which is the
        // contract enforcing it rather than a rule someone has to remember.
        expect(
          CreateRecordRequest().info_.byName.keys,
          isNot(contains('id')),
          reason: 'a create request carrying an id would let a client choose its own identity',
        );
      });

      test('a Category survives the round trip field for field', () {
        final original = Category(
          id: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
          title: 'Food',
          iconKey: 'food',
          description: 'Groceries and eating out',
          // 0xFF2196F3 — opaque blue. Above 2^31, so a signed 32-bit reading of it would come back
          // negative; uint32 is the reason it does not.
          colorArgb: 0xFF2196F3,
        );

        final decoded = roundTrip(original, format, Category.new);

        expect(decoded.id, original.id);
        expect(decoded.title, original.title);
        expect(decoded.iconKey, original.iconKey);
        expect(decoded.description, original.description);
        expect(decoded.colorArgb, 0xFF2196F3);
        expect(decoded, original);
      });

      test('Settings round-trips, and names an owner nowhere', () {
        final decoded = roundTrip(Settings(mainCurrency: 'PLN'), format, Settings.new);

        expect(decoded.mainCurrency, 'PLN');
        // A singleton addressed by the token: the URL carries no id and the message carries no
        // owner. A client that could name an owner could name someone else's.
        expect(Settings().info_.byName.keys, isNot(contains('userId')));
        expect(Settings().info_.byName.keys, isNot(contains('id')));
      });

      test('an empty main_currency round-trips as empty — "reset to default", not a value', () {
        // proto3 has no presence for a string, so "" and unset are the same bytes. The contract
        // resolves that by assigning "" a meaning on each side rather than leaving it ambiguous:
        // on a request it means reset to the default, and a response never carries it because the
        // server resolves the default before answering. The wire must carry "" faithfully for
        // either rule to be implementable.
        final decoded = roundTrip(UpdateSettingsRequest(), format, UpdateSettingsRequest.new);

        expect(decoded.mainCurrency, isEmpty);
      });

      test('the AccountType zero value round-trips as UNSPECIFIED, not as CASH', () {
        // proto3 has no field presence for enums: an unset type IS the zero value. The contract
        // puts UNSPECIFIED there so an omission decodes to "nobody said", which the server
        // rejects — rather than to a plausible default that silently writes the wrong account
        // type and passes every test, because CASH is a valid answer.
        final decoded = roundTrip(Account(name: 'No type given'), format, Account.new);

        expect(decoded.type, AccountType.ACCOUNT_TYPE_UNSPECIFIED);
      });

      // -------------------------------------------------------------------------------------
      // Money. This is the defect the int64-minor-units type exists to remove, so it is asserted
      // rather than assumed.
      // -------------------------------------------------------------------------------------

      test('money whose decimal form is unrepresentable in binary floating point is exact', () {
        // The canonical demonstration: 0.1 + 0.2 != 0.3 as doubles. None of the three values has
        // an exact binary representation, and the error survives into the sum.
        expect(0.1 + 0.2 == 0.3, isFalse, reason: 'the premise this field type is chosen against');

        // The same three amounts as minor units, through both wire formats.
        final ten = roundTrip(Record(amountMinor: Int64(10)), format, Record.new); // 0.10
        final twenty = roundTrip(Record(amountMinor: Int64(20)), format, Record.new); // 0.20

        expect(ten.amountMinor, Int64(10));
        expect(twenty.amountMinor, Int64(20));
        // Exact under addition, which is the whole property: an expense tracker sums thousands of
        // these, and a total wrong by a cent is wrong.
        expect(ten.amountMinor + twenty.amountMinor, Int64(30)); // 0.30, exactly
      });

      test('an amount beyond a double\'s exact integer range survives', () {
        // 2^53 + 1 is the smallest positive integer a double CANNOT represent — it rounds to 2^53.
        // Nothing in a personal budget reaches it, and that is beside the point: the assertion is
        // that this value never passes through a float on either wire format. Canonical proto3
        // JSON encodes int64 AS A STRING for exactly this reason, so the JSON mode is the one that
        // would fail if the contract had chosen a double or a JSON number.
        final beyondDouble = Int64(9007199254740993);
        expect(beyondDouble.toDouble().toStringAsFixed(0), '9007199254740992');

        final decoded = roundTrip(
          Account(balances: [CurrencyBalance(currency: 'PLN', amountMinor: beyondDouble)]),
          format,
          Account.new,
        );

        expect(decoded.balances.single.amountMinor, beyondDouble);
        expect(decoded.balances.single.amountMinor.toString(), '9007199254740993');
      });

      test('balances in different currencies stay separate, and are never summed', () {
        // The multi-currency rule the arithmetic depends on, asserted on the wire rather than left
        // to Phase 4 to remember. Prudent does no FX: there is no rate source, no rate date and no
        // base currency, so 100 PLN + 100 EUR has no value to be. A total is per-currency, and
        // this test exists so that a later change collapsing balances into one number fails here
        // instead of shipping a plausible wrong number to a budget screen.
        final decoded = roundTrip(
          Account(
            balances: [
              CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000)),
              CurrencyBalance(currency: 'EUR', amountMinor: Int64(10000)),
            ],
          ),
          format,
          Account.new,
        );

        expect(decoded.balances.length, 2);
        // Identical amounts, different currencies: equal as numbers, not interchangeable as money.
        expect(decoded.balances[0].amountMinor, decoded.balances[1].amountMinor);
        expect(decoded.balances[0].currency, isNot(decoded.balances[1].currency));

        final byCurrency = {
          for (final b in decoded.balances) b.currency: b.amountMinor,
        };
        expect(byCurrency, {'PLN': Int64(10000), 'EUR': Int64(10000)});
      });
    });
  }

  test('the two wire formats agree with each other, not merely with themselves', () {
    // Each mode round-tripping cleanly on its own would still permit them to disagree — which is
    // the failure that matters, because the same record is written by one client and read by
    // another that negotiated the other format.
    final original = Record(
      id: '6f9619ff-8b86-d011-b42d-00c04fc964ff',
      title: 'Coffee',
      amountMinor: Int64(1499),
      currency: 'PLN',
      date: '2026-08-15',
      categoryId: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
      accountId: '018f3a1b-2c4d-7e8f-9a0b-1c2d3e4f5a6b',
    );

    final viaJson = roundTrip(original, ZenTransportFormat.json, Record.new);
    final viaProtobuf = roundTrip(original, ZenTransportFormat.protobuf, Record.new);

    expect(viaJson, viaProtobuf);
  });

  test('canonical proto3 JSON encodes int64 as a string', () {
    // Pinned deliberately, because it is the contract's most surprising property and both the
    // Quarkus server (JsonFormat) and any admin TypeScript have to agree with it. A change here is
    // a wire-compatibility change, not an implementation detail.
    final bytes = ZenProtoCodec.encode(
      Record(amountMinor: Int64(1234)),
      ZenTransportFormat.json,
    );

    expect(String.fromCharCodes(bytes), contains('"amountMinor":"1234"'));
  });
}
