// Unit 7's rules (ADR-118) on a real store: what counts as spend, the window boundaries, one
// currency at a time, the order, the empty answer, every refusal — and on two real devices, that a
// record the devices disagree about never counts as if it were settled and the answer says so. The
// comparison with the server's own figures is the parity suite (analytics.json, analytics_large).
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/analytics.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

import 'support/two_devices.dart';

T ok<T>(ZenResult<T> result) => Device.ok(result);

void main() {
  group('on one device', () {
    late Directory directory;
    late ZenStore zen;
    late Ledger ledger;
    late Analytics analytics;
    late String wallet;
    late String food;
    late String fun;
    // 2026-11-16 UTC, the day this unit was built; "the current period" is read from it.
    var clock = DateTime.utc(2026, 11, 16, 12);

    setUp(() async {
      clock = DateTime.utc(2026, 11, 16, 12);
      directory = await Directory.systemTemp.createTemp('prudent_analytics_test');
      zen = ok(await ZenStore.open(directory, deviceName: 'test', key: List.filled(32, 3)));
      final store = PrudentLocalStore(zen);
      ledger = Ledger(store);
      analytics = Analytics(store, now: () => clock);
      wallet = ok(
        await ledger.createAccount(
          wire.CreateAccountRequest(
            name: 'Wallet',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            balances: [
              wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(100000)),
              wire.CurrencyBalance(currency: 'EUR', amountMinor: Int64(100000)),
            ],
          ),
        ),
      ).value.id;
      food = ok(
        await ledger.createCategory(wire.CreateCategoryRequest(title: 'Food', iconKey: 'food')),
      ).id;
      fun = ok(
        await ledger.createCategory(wire.CreateCategoryRequest(title: 'Fun', iconKey: 'food')),
      ).id;
    });
    tearDown(() async {
      await zen.close();
      await directory.delete(recursive: true);
    });

    Future<String> spend(
      int amount,
      String date, {
      String? category,
      String currency = 'PLN',
    }) async => ok(
      await ledger.createRecord(
        wire.CreateRecordRequest(
          title: 'x',
          amountMinor: Int64(amount),
          date: date,
          categoryId: category ?? food,
          accountId: wallet,
          currency: currency,
        ),
      ),
    ).id;

    Map<String, int> byCategory(Settled<wire.SpendByCategoryResponse> answer) => {
      for (final item in answer.value.items) item.categoryId: item.amountMinor.toInt(),
    };

    Map<String, int> byPeriod(Settled<wire.SpendByPeriodResponse> answer) => {
      for (final p in answer.value.periods) p.period: p.amountMinor.toInt(),
    };

    int? status(ZenResult<Object?> result) => LedgerErrors.statusOf(result.errorOrNull!);

    test('an empty ledger answers an empty list, not a zero, and echoes the currency', () async {
      final answer = ok(await analytics.spendByCategory(currency: ' pln ', year: 2026));
      expect(answer.value.currency, 'PLN');
      expect(answer.value.items, isEmpty);
      expect(answer.isSettled, isTrue);
      final periods = ok(
        await analytics.spendByPeriod(currency: 'PLN', granularity: 'month', count: 3),
      );
      expect(periods.value.periods, isEmpty);
      expect(periods.value.granularity, wire.Granularity.GRANULARITY_MONTH);
    });

    test('only expenses count: income and refunds are not netted, and the cent is exact', () async {
      await spend(-1250, '2026-03-05');
      await spend(-1, '2026-03-06', category: fun);
      await spend(250000, '2026-03-07');
      await spend(400, '2026-03-08');
      final answer = ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 3));
      expect(byCategory(answer), {food: 1250, fun: 1});
    });

    test('a month includes its first and last day and nothing next to them', () async {
      await spend(-1, '2026-02-28');
      await spend(-10, '2026-03-01');
      await spend(-100, '2026-03-31');
      await spend(-1000, '2026-04-01');
      final march = ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 3));
      expect(byCategory(march), {food: 110});
      final year = ok(await analytics.spendByCategory(currency: 'PLN', year: 2026));
      expect(byCategory(year), {food: 1111});
    });

    test(
      'February 29 belongs to February of a leap year; the year edges are in their year',
      () async {
        await spend(-5, '2024-02-29');
        await spend(-6, '2024-01-01');
        await spend(-7, '2024-12-31');
        await spend(-8, '2023-12-31');
        await spend(-9, '2025-01-01');
        expect(
          byCategory(ok(await analytics.spendByCategory(currency: 'PLN', year: 2024, month: 2))),
          {food: 5},
        );
        expect(byCategory(ok(await analytics.spendByCategory(currency: 'PLN', year: 2024))), {
          food: 18,
        });
      },
    );

    test('one currency at a time, never summed', () async {
      await spend(-100, '2026-03-05');
      await spend(-777, '2026-03-05', currency: 'EUR');
      expect(byCategory(ok(await analytics.spendByCategory(currency: 'pln', year: 2026))), {
        food: 100,
      });
      expect(byCategory(ok(await analytics.spendByCategory(currency: 'EUR', year: 2026))), {
        food: 777,
      });
      expect(ok(await analytics.spendByCategory(currency: 'CHF', year: 2026)).value.items, isEmpty);
    });

    test('a transfer and a correction are not spending', () async {
      final other = ok(
        await ledger.createAccount(
          wire.CreateAccountRequest(
            name: 'Bank',
            type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(50000))],
          ),
        ),
      ).value.id;
      await spend(-100, '2026-03-05');
      ok(
        await ledger.createTransfer(
          wire.CreateTransferRequest(
            title: 'Move',
            fromAccountId: other,
            toAccountId: wallet,
            fromAmountMinor: Int64(3000),
            fromCurrency: 'PLN',
            toAmountMinor: Int64(3000),
            toCurrency: 'PLN',
            date: '2026-03-05',
          ),
        ),
      );
      ok(
        await ledger.createCorrection(
          wire.CreateCorrectionRequest(
            accountId: wallet,
            currency: 'PLN',
            balanceMinor: Int64(-5000),
            date: '2026-03-06',
          ),
        ),
      );
      expect(
        byCategory(ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 3))),
        {food: 100},
      );
    });

    test('an edit or a delete moves the figure; an archived category keeps its spend', () async {
      final id = await spend(-100, '2026-03-05');
      ok(
        await ledger.updateRecord(
          id,
          wire.UpdateRecordRequest(
            title: 'x',
            amountMinor: Int64(-400),
            date: '2026-04-02',
            categoryId: fun,
            accountId: wallet,
            currency: 'PLN',
          ),
        ),
      );
      expect(
        ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 3)).value.items,
        isEmpty,
      );
      expect(
        byCategory(ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 4))),
        {fun: 400},
      );
      ok(await ledger.archiveCategory(fun));
      expect(
        byCategory(ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 4))),
        {fun: 400},
      );
      ok(await ledger.deleteRecord(id));
      expect(
        ok(await analytics.spendByCategory(currency: 'PLN', year: 2026, month: 4)).value.items,
        isEmpty,
      );
    });

    test('categories come in id order, periods oldest to newest', () async {
      await spend(-1, '2026-01-10', category: fun);
      await spend(-2, '2026-01-11');
      final ids = ok(await analytics.spendByCategory(currency: 'PLN', year: 2026)).value.items
          .map((i) => i.categoryId)
          .toList();
      expect(ids, [...ids]..sort());
      await spend(-3, '2025-11-01');
      await spend(-4, '2026-09-01');
      await spend(-5, '2026-11-30');
      final periods = ok(
        await analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 60),
      ).value.periods.map((p) => p.period).toList();
      expect(periods, ['2025-11', '2026-01', '2026-09', '2026-11']);
    });

    test(
      'the trailing window ends with the current month in UTC and counts count buckets',
      () async {
        // 2026-11: count 3 is September to November; a record in August is outside it.
        await spend(-1, '2026-08-31');
        await spend(-10, '2026-09-01');
        await spend(-100, '2026-11-30');
        await spend(-1000, '2026-12-01');
        expect(
          byPeriod(
            ok(await analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 3)),
          ),
          {'2026-09': 10, '2026-11': 100},
        );
        // The anchor is UTC: just before midnight UTC is still November, an hour later is December.
        clock = DateTime.utc(2026, 11, 30, 23, 59);
        expect(
          byPeriod(
            ok(await analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 1)),
          ),
          {'2026-11': 100},
        );
        clock = DateTime.utc(2026, 12, 1);
        expect(
          byPeriod(
            ok(await analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 1)),
          ),
          {'2026-12': 1000},
        );
        // A non-UTC instant is converted, not read in its own zone.
        clock = DateTime.parse('2026-11-30T23:30:00-05:00');
        expect(
          byPeriod(
            ok(await analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 1)),
          ),
          {'2026-12': 1000},
        );
      },
    );

    test('by year: the current year is the last bucket', () async {
      clock = DateTime.utc(2026, 11, 16);
      await spend(-1, '2024-06-01');
      await spend(-10, '2025-06-01');
      await spend(-100, '2026-06-01');
      await spend(-1000, '2023-12-31');
      final answer = ok(
        await analytics.spendByPeriod(currency: 'PLN', granularity: 'Year', count: 3),
      );
      expect(answer.value.granularity, wire.Granularity.GRANULARITY_YEAR);
      expect(byPeriod(answer), {'2024': 1, '2025': 10, '2026': 100});
    });

    test('every refusal is the server\'s 400, in its order', () async {
      Future<void> refused(Future<ZenResult<Object?>> call) async =>
          expect(status(await call), 400);
      await refused(analytics.spendByCategory(currency: null, year: 2026));
      await refused(analytics.spendByCategory(currency: '', year: 2026));
      await refused(analytics.spendByCategory(currency: 'ABC', year: 2026));
      await refused(analytics.spendByCategory(currency: 'PLN', year: null));
      await refused(analytics.spendByCategory(currency: 'PLN', year: 2026, month: 0));
      await refused(analytics.spendByCategory(currency: 'PLN', year: 2026, month: 13));
      await refused(analytics.spendByCategory(currency: 'PLN', year: 2000000000));
      await refused(analytics.spendByPeriod(currency: null, granularity: 'MONTH', count: 1));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: null, count: 1));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'WEEK', count: 1));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: null));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 0));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 61));
      // Full-width letters are not MONTH.
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'ＭＯＮＴＨ', count: 1));
      await refused(analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: -1));
      expect(
        ok(await analytics.spendByPeriod(currency: 'PLN', granularity: 'mOnTh', count: 60))
            .value
            .periods,
        isEmpty,
      );
    });

    test('a sum that leaves the 64-bit range is an error, never a wrapped figure', () async {
      final big = -(1 << 62);
      await spend(big, '2026-03-05');
      await spend(big, '2026-03-06');
      await spend(big, '2026-03-07');
      final failed = await analytics.spendByCategory(currency: 'PLN', year: 2026);
      expect(failed.isFailure, isTrue);
      expect(status(failed), isNull);
    });
  });

  group('on two devices', () {
    late TwoDevices devices;
    late Ledger laptop;
    late Ledger phone;
    late Analytics laptopAnalytics;
    late Analytics phoneAnalytics;
    late String wallet;
    late String food;
    late String fun;
    late String tea;

    setUp(() async {
      devices = await TwoDevices.create();
      laptop = Ledger(devices.laptop.store);
      phone = Ledger(devices.phone.store);
      final clock = DateTime.utc(2026, 11, 16);
      laptopAnalytics = Analytics(devices.laptop.store, now: () => clock);
      phoneAnalytics = Analytics(devices.phone.store, now: () => clock);
      wallet = ok(
        await laptop.createAccount(
          wire.CreateAccountRequest(
            name: 'Wallet',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(100000))],
          ),
        ),
      ).value.id;
      food = ok(
        await laptop.createCategory(wire.CreateCategoryRequest(title: 'Food', iconKey: 'food')),
      ).id;
      fun = ok(
        await laptop.createCategory(wire.CreateCategoryRequest(title: 'Fun', iconKey: 'food')),
      ).id;
      tea = ok(
        await laptop.createCategory(wire.CreateCategoryRequest(title: 'Tea', iconKey: 'food')),
      ).id;
      await devices.sync();
    });
    tearDown(() async => devices.dispose());

    Future<String> add(
      Ledger on,
      int amount, {
      String date = '2026-03-05',
      String? category,
    }) async => ok(
      await on.createRecord(
        wire.CreateRecordRequest(
          title: 'x',
          amountMinor: Int64(amount),
          date: date,
          categoryId: category ?? food,
          accountId: wallet,
          currency: 'PLN',
        ),
      ),
    ).id;

    Future<void> edit(
      Ledger on,
      String id, {
      int amount = -1000,
      String date = '2026-03-05',
      String? category,
      String? account,
      String? note,
    }) async => ok(
      await on.updateRecord(
        id,
        wire.UpdateRecordRequest(
          title: 'x',
          amountMinor: Int64(amount),
          date: date,
          categoryId: category ?? food,
          accountId: account ?? wallet,
          currency: 'PLN',
          note: note,
        ),
      ),
    );

    Future<List<(Settled<wire.SpendByCategoryResponse>, Settled<wire.SpendByPeriodResponse>)>>
    both() async => [
      for (final a in [laptopAnalytics, phoneAnalytics])
        (
          ok(await a.spendByCategory(currency: 'PLN', year: 2026, month: 3)),
          ok(await a.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 12)),
        ),
    ];

    test(
      'two amounts for one record: it counts in no figure on either device, and is named',
      () async {
        final disputed = await add(laptop, -1000);
        await add(laptop, -500, category: fun);
        await devices.sync();
        await edit(laptop, disputed, amount: -1200);
        await edit(phone, disputed, amount: -1800);
        await devices.sync();
        for (final (byCategory, byPeriod) in await both()) {
          expect(
            {for (final i in byCategory.value.items) i.categoryId: i.amountMinor.toInt()},
            {fun: 500},
          );
          expect(byPeriod.value.periods.single.amountMinor.toInt(), 500);
          expect(byCategory.unsettled, {
            wallet: [disputed],
          });
          expect(byPeriod.unsettled, {
            wallet: [disputed],
          });
        }
        // The person settles it once; both devices then count it.
        final conflict = ok(devices.phone.store.records.conflicts()).single;
        final chosen = conflict.sides.firstWhere(
          (s) => s.value!.posting.amountMinor == Int64(-1200),
        );
        ok(await devices.phone.store.records.resolve(disputed, chosen.value));
        await devices.sync();
        for (final (byCategory, byPeriod) in await both()) {
          expect(byCategory.isSettled, isTrue);
          expect(byPeriod.isSettled, isTrue);
          expect(byPeriod.value.periods.single.amountMinor.toInt(), 1700);
        }
      },
    );

    // Both devices move the record to one account, the laptop merges the two identical moves into
    // one version under the phone's name, and the phone changes the amount before it hears of that:
    // two amounts survive, and `ZenConflict.sides` shows each device only one (jZenDev/jZen#286). So
    // the sides cannot say that a conflict on `posting` is about the account alone, and any such
    // conflict leaves the record out (jlogicsoftware/prudent#276, item 1).
    test('two surviving amounts under one author are still disputed', () async {
      final bank = ok(
        await laptop.createAccount(
          wire.CreateAccountRequest(
            name: 'Bank',
            type: wire.AccountType.ACCOUNT_TYPE_CASH,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(100000))],
          ),
        ),
      ).value.id;
      await devices.sync();
      final disputed = await add(laptop, -1000);
      await devices.sync();
      await edit(laptop, disputed, account: bank);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await edit(phone, disputed, account: bank);
      await devices.phone.syncNow();
      await devices.laptop.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await edit(phone, disputed, account: bank, amount: -1800);
      await devices.sync();
      for (final (byCategory, byPeriod) in await both()) {
        expect(byCategory.value.items, isEmpty);
        expect(byPeriod.value.periods, isEmpty);
        expect(byCategory.isSettled, isFalse);
      }
    });

    test('two dates for one record: left out of both figures', () async {
      final disputed = await add(laptop, -1000);
      await devices.sync();
      await edit(laptop, disputed, date: '2026-03-06');
      await edit(phone, disputed, date: '2026-05-06');
      await devices.sync();
      for (final (byCategory, byPeriod) in await both()) {
        expect(byCategory.value.items, isEmpty);
        expect(byPeriod.value.periods, isEmpty);
        expect(byCategory.unsettled, {
          wallet: [disputed],
        });
      }
    });

    test(
      'two categories: the category figure leaves it out, the period figure counts it',
      () async {
        final disputed = await add(laptop, -1000);
        await devices.sync();
        await edit(laptop, disputed, category: tea);
        await edit(phone, disputed, category: fun);
        await devices.sync();
        for (final (byCategory, byPeriod) in await both()) {
          expect(byCategory.value.items, isEmpty);
          expect(byCategory.unsettled, {
            wallet: [disputed],
          });
          expect(byPeriod.value.periods.single.amountMinor.toInt(), 1000);
          expect(byPeriod.isSettled, isTrue);
        }
      },
    );

    test('a delete against an edit: the record counts in no figure until settled', () async {
      final disputed = await add(laptop, -1000);
      await devices.sync();
      ok(await laptop.deleteRecord(disputed));
      await edit(phone, disputed, amount: -2000);
      await devices.sync();
      for (final (byCategory, byPeriod) in await both()) {
        expect(byCategory.value.items, isEmpty);
        expect(byPeriod.value.periods, isEmpty);
        expect(byCategory.unsettled, {
          wallet: [disputed],
        });
      }
    });

    test('two notes for one record: money agreed, counted, nothing left out', () async {
      final disputed = await add(laptop, -1000);
      await devices.sync();
      await edit(laptop, disputed, note: 'rye');
      await edit(phone, disputed, note: 'spelt');
      await devices.sync();
      for (final (byCategory, byPeriod) in await both()) {
        expect(byCategory.value.items.single.amountMinor.toInt(), 1000);
        expect(byPeriod.value.periods.single.amountMinor.toInt(), 1000);
        expect(byCategory.isSettled, isTrue);
        expect(byPeriod.isSettled, isTrue);
      }
    });

    test('a dispute outside the figure does not make it say it left something out', () async {
      final disputed = await add(laptop, -1000, date: '2025-01-05');
      await add(laptop, -300);
      await devices.sync();
      await edit(laptop, disputed, amount: -1200, date: '2025-01-05');
      await edit(phone, disputed, amount: -1800, date: '2025-01-05');
      await devices.sync();
      for (final (byCategory, byPeriod) in await both()) {
        // March 2026 and the last 12 months do not include January 2025.
        expect(byCategory.isSettled, isTrue);
        expect(byPeriod.isSettled, isTrue);
        expect(byCategory.value.items.single.amountMinor.toInt(), 300);
      }
    });
  });
}
