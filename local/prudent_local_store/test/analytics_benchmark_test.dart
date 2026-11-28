// The benchmark (tool/analytics_benchmark.dart) must not time a read that read nothing: each of its
// checks refuses a failure, an empty answer and a misshapen one, and the benchmark itself passes its
// own checks on a small ledger. No time is asserted here.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/analytics.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

import '../tool/analytics_benchmark.dart';

void main() {
  ZenResult<Settled<T>> settled<T>(T value, [Map<String, List<String>> unsettled = const {}]) =>
      ZenResult.ok(Settled(value, unsettled));

  final refuses = throwsStateError;

  test('the benchmark answers every question on a small ledger, and its checks pass', () async {
    final report = await runAnalyticsBenchmark(sizes: [1500], repeats: 1);
    expect(report.where((line) => line.contains(' median ')), hasLength(6));
  });

  group('spend by category', () {
    wire.CategorySpend item(String id, int amount) =>
        wire.CategorySpend(categoryId: id, amountMinor: Int64(amount));
    void check(Object? answer) => checkSpendByCategory('q', answer, currency: 'PLN');
    ZenResult<Object> answer(List<wire.CategorySpend> items, {String currency = 'PLN'}) =>
        settled(wire.SpendByCategoryResponse(currency: currency, items: items));

    test('accepts an answer with spend', () => check(answer([item('a', 1), item('b', 2)])));

    test('refuses a failure, no answer and an empty or misshapen one', () {
      expect(() => check(ZenResult<Object>.err(ZenUnknownError('x'))), refuses);
      expect(() => check(null), refuses);
      expect(() => check(settled(wire.SpendByPeriodResponse())), refuses);
      expect(() => check(answer([])), refuses);
      expect(() => check(answer([item('a', 1)], currency: 'EUR')), refuses);
      expect(() => check(answer([item('', 1)])), refuses);
      expect(() => check(answer([item('a', 0)])), refuses);
      expect(() => check(answer([item('a', 1), item('a', 2)])), refuses);
      expect(
        () => check(
          settled(wire.SpendByCategoryResponse(currency: 'PLN', items: [item('a', 1)]), {
            'account': ['record'],
          }),
        ),
        refuses,
      );
    });
  });

  group('spend by period', () {
    void check(Object? answer) => checkSpendByPeriod(
      'q',
      answer,
      currency: 'PLN',
      granularity: wire.Granularity.GRANULARITY_MONTH,
      count: 2,
    );
    ZenResult<Object> answer(
      Map<String, int> periods, {
      String currency = 'PLN',
      wire.Granularity granularity = wire.Granularity.GRANULARITY_MONTH,
    }) => settled(
      wire.SpendByPeriodResponse(
        currency: currency,
        granularity: granularity,
        periods: [
          for (final MapEntry(:key, :value) in periods.entries)
            wire.PeriodSpend(period: key, amountMinor: Int64(value)),
        ],
      ),
    );

    test('accepts periods oldest to newest', () => check(answer({'2025-12': 1, '2026-01': 2})));

    test('refuses a failure and an empty or misshapen answer', () {
      expect(() => check(ZenResult<Object>.err(ZenUnknownError('x'))), refuses);
      expect(() => check(settled(wire.SpendByCategoryResponse())), refuses);
      expect(() => check(answer({})), refuses);
      // Each of these has the two periods asked for, and one thing wrong.
      const two = {'2025-12': 1, '2026-01': 2};
      expect(() => check(answer(two, currency: 'EUR')), refuses);
      expect(() => check(answer(two, granularity: wire.Granularity.GRANULARITY_YEAR)), refuses);
      expect(() => check(answer({'2025': 1, '2026': 2})), refuses);
      expect(() => check(answer({'2025-12': 1, '2026-01': 0})), refuses);
      expect(() => check(answer({'2026-02': 1, '2026-01': 2})), refuses);
      // Fewer periods than the window holds, and more.
      expect(() => check(answer({'2026-01': 1})), refuses);
      expect(() => check(answer({'2025-11': 1, '2025-12': 2, '2026-01': 3})), refuses);
    });
  });

  group('the overview', () {
    void check(Object? answer) => checkOverview('q', answer, accounts: 2, opening: 100);
    wire.Account account(String id, [List<int> balances = const [100]]) => wire.Account(
      id: id,
      balances: [
        for (final amount in balances)
          wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(amount)),
      ],
    );
    ZenResult<Object> answer(List<wire.Account> accounts) =>
        settled(wire.ListAccountsResponse(accounts: accounts));

    test('accepts accounts whose balances moved', () {
      check(
        answer([
          account('a'),
          account('b', [90]),
        ]),
      );
    });

    test('refuses a failure, missing accounts or balances, and opening balances only', () {
      expect(() => check(ZenResult<Object>.err(ZenUnknownError('x'))), refuses);
      expect(() => check(answer([])), refuses);
      expect(
        () => check(
          answer([
            account('a', [90]),
          ]),
        ),
        refuses,
      );
      expect(
        () => check(
          answer([
            account('a', [90]),
            account('b', []),
          ]),
        ),
        refuses,
      );
      expect(() => check(answer([account('a'), account('b')])), refuses);
    });
  });
}
