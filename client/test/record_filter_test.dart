import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/record/record_filter.dart';

void main() {
  group('RecordFilter.isEmpty', () {
    test('empty is empty', () {
      expect(RecordFilter.empty.isEmpty, isTrue);
    });

    test('any single criterion makes it non-empty', () {
      expect(const RecordFilter(accountId: 'a1').isEmpty, isFalse);
      expect(RecordFilter(dateFrom: DateTime(2026, 8, 1)).isEmpty, isFalse);
      expect(const RecordFilter(type: RecordFilterType.income).isEmpty, isFalse);
      expect(RecordFilter(amountMin: Int64(1)).isEmpty, isFalse);
    });

    test('a blank or whitespace-only search is treated as no filter', () {
      expect(const RecordFilter(search: '').isEmpty, isTrue);
      expect(const RecordFilter(search: '   ').isEmpty, isTrue);
      expect(const RecordFilter(search: 'coffee').isEmpty, isFalse);
    });
  });

  group('RecordFilter.toQueryParameters', () {
    test('empty filter produces no query parameters', () {
      expect(RecordFilter.empty.toQueryParameters(), isEmpty);
    });

    test('every criterion maps to its own query parameter name', () {
      final filter = RecordFilter(
        dateFrom: DateTime(2026, 1, 5),
        dateTo: DateTime(2026, 1, 31),
        accountId: 'acc-1',
        categoryId: 'cat-1',
        type: RecordFilterType.transfer,
        amountMin: Int64(1000),
        amountMax: Int64(5000),
        search: '  groceries  ',
      );

      expect(filter.toQueryParameters(), {
        'dateFrom': '2026-01-05',
        'dateTo': '2026-01-31',
        'accountId': 'acc-1',
        'categoryId': 'cat-1',
        'type': 'transfer',
        'amountMin': '1000',
        'amountMax': '5000',
        // Trimmed, matching the server's own trim on the same parameter.
        'search': 'groceries',
      });
    });

    test('a criterion left null is simply absent, not sent blank', () {
      final query = const RecordFilter(accountId: 'a1').toQueryParameters();
      expect(query.keys, ['accountId']);
    });
  });

  group('RecordFilter equality', () {
    test('two filters with the same criteria compare equal', () {
      final a = RecordFilter(accountId: 'a1', amountMin: Int64(5));
      final b = RecordFilter(accountId: 'a1', amountMin: Int64(5));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a differing criterion breaks equality', () {
      final a = const RecordFilter(accountId: 'a1');
      final b = const RecordFilter(accountId: 'a2');
      expect(a, isNot(equals(b)));
    });
  });
}
