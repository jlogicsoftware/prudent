/// How long the analytics screen and the overview take at the size of a real ledger (unit 7,
/// ADR-118). Pure Dart: `dart run tool/analytics_benchmark.dart` on the VM, and the same
/// [runAnalyticsBenchmark] inside a throwaway Flutter app on a device or emulator (unit 12 is the
/// release gate that must run it on a real device).
///
/// The ledger is built the quick way — accounts and categories through the [Ledger], records
/// written in batches straight to the store — because building 50 000 records one `createRecord` at
/// a time is quadratic and measures the write path, which is not what is asked. What is timed is
/// the READ: the questions the screens ask. Every figure is a median of [repeats] runs after one
/// warm-up run, and the first (cold) run is reported too. Every answer is then checked, outside the
/// timed span: a refusal, an empty answer or a misshapen one stops the run, so no figure here is the
/// time of a read that read nothing. The ledger spans six years, so every trailing window asked must
/// answer all its periods: a size too small to put spend in each of the last 60 months stops the run.
///
/// Synthetic data only: a seeded random ledger, nothing real.
library;

import 'dart:io';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/analytics.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

Future<void> main(List<String> args) async {
  final sizes = args.isEmpty ? const [5000, 20000, 50000] : args.map(int.parse).toList();
  final lines = await runAnalyticsBenchmark(sizes: sizes, log: stdout.writeln);
  stdout.writeln(lines.join('\n'));
}

/// Runs the benchmark for each ledger size and returns its report; [log] sees each line as it is
/// produced (a device has no stdout to watch).
Future<List<String>> runAnalyticsBenchmark({
  required List<int> sizes,
  int repeats = 7,
  void Function(String line)? log,
}) async {
  final report = <String>[];
  void say(String line) {
    report.add(line);
    log?.call(line);
  }

  say('platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  say('cpus: ${Platform.numberOfProcessors}');
  for (final size in sizes) {
    final directory = await Directory.systemTemp.createTemp('analytics_bench_');
    final zen = _ok(await ZenStore.open(directory, deviceName: 'bench', key: List.filled(32, 9)));
    try {
      final store = PrudentLocalStore(zen);
      final ledger = Ledger(store);
      final build = Stopwatch()..start();
      final ids = await _populate(store, ledger, size);
      say('--- $size records (built in ${build.elapsed.inMilliseconds} ms) ---');
      final analytics = Analytics(store);
      final year = DateTime.now().toUtc().year;
      _Question byCategory({int? month}) => (
        ask: () => analytics.spendByCategory(currency: 'PLN', year: year - 1, month: month),
        check: (what, answer) => checkSpendByCategory(what, answer, currency: 'PLN'),
      );
      _Question byPeriod(String granularity, int count) => (
        ask: () => analytics.spendByPeriod(currency: 'PLN', granularity: granularity, count: count),
        check: (what, answer) => checkSpendByPeriod(
          what,
          answer,
          currency: 'PLN',
          granularity: granularity == 'MONTH'
              ? wire.Granularity.GRANULARITY_MONTH
              : wire.Granularity.GRANULARITY_YEAR,
          count: count,
        ),
      );
      final questions = <String, _Question>{
        'spend by category, one year': byCategory(),
        'spend by category, one month': byCategory(month: 6),
        'spend by month, last 12': byPeriod('MONTH', 12),
        'spend by month, last 60': byPeriod('MONTH', 60),
        'spend by year, last 5': byPeriod('YEAR', 5),
        'overview: every account with its balances': (
          ask: () => ledger.listAccounts(),
          check: (what, answer) =>
              checkOverview(what, answer, accounts: ids.accounts, opening: _opening),
        ),
      };
      for (final MapEntry(:key, value: question) in questions.entries) {
        final cold = Stopwatch()..start();
        final first = await question.ask();
        final coldMs = cold.elapsedMicroseconds / 1000;
        question.check(key, first);
        final times = <double>[];
        for (var i = 0; i < repeats; i++) {
          final run = Stopwatch()..start();
          final answer = await question.ask();
          times.add(run.elapsedMicroseconds / 1000);
          question.check(key, answer);
        }
        times.sort();
        say(
          '${key.padRight(44)} first ${coldMs.toStringAsFixed(1).padLeft(8)} ms   '
          'median ${times[times.length ~/ 2].toStringAsFixed(1).padLeft(8)} ms   '
          'max ${times.last.toStringAsFixed(1).padLeft(8)} ms',
        );
      }
      say('(${ids.records} expenses and ${ids.other} other records in ${ids.accounts} accounts)');
    } finally {
      await zen.close();
      await directory.delete(recursive: true);
    }
  }
  return report;
}

/// One timed question and what its answer must hold.
typedef _Question = ({
  Future<Object?> Function() ask,
  void Function(String what, Object? answer) check,
});

/// The settled value of [answer], or a [StateError]: a failure, something that is not an answer of
/// this shape, or one that left records out (nothing here is in conflict).
T _answered<T>(String what, Object? answer) => switch (answer) {
  ZenFailure(:final error) => throw StateError('$what failed: $error'),
  ZenSuccess(data: Settled(:final T value, isSettled: true)) => value,
  _ => throw StateError('$what did not answer a settled $T: $answer'),
};

void _require(bool holds, String what, String lack) {
  if (!holds) throw StateError('$what answered $lack.');
}

/// Spend by category in [currency]: at least one item, each of its own category with spend in it.
void checkSpendByCategory(String what, Object? answer, {required String currency}) {
  final value = _answered<wire.SpendByCategoryResponse>(what, answer);
  _require(value.currency == currency, what, 'in "${value.currency}", not $currency');
  _require(value.items.isNotEmpty, what, 'no category');
  _require(
    value.items.every((i) => i.categoryId.isNotEmpty && i.amountMinor > Int64.ZERO),
    what,
    'an item with no category or no spend',
  );
  _require(
    {for (final i in value.items) i.categoryId}.length == value.items.length,
    what,
    'one category twice',
  );
}

/// Spend by period in [currency]: all [count] periods of [granularity], oldest to newest, each with
/// spend in it.
void checkSpendByPeriod(
  String what,
  Object? answer, {
  required String currency,
  required wire.Granularity granularity,
  required int count,
}) {
  final value = _answered<wire.SpendByPeriodResponse>(what, answer);
  _require(value.currency == currency, what, 'in "${value.currency}", not $currency');
  _require(value.granularity == granularity, what, '${value.granularity}, not $granularity');
  _require(value.periods.length == count, what, '${value.periods.length} periods, not $count');
  final label = granularity == wire.Granularity.GRANULARITY_MONTH
      ? RegExp(r'^\d{4}-\d{2}$')
      : RegExp(r'^\d{4}$');
  var previous = '';
  for (final period in value.periods) {
    _require(label.hasMatch(period.period), what, 'the period "${period.period}"');
    _require(period.period.compareTo(previous) > 0, what, 'periods out of order');
    _require(period.amountMinor > Int64.ZERO, what, 'a period with no spend');
    previous = period.period;
  }
}

/// The overview: [accounts] accounts, each with one balance, and not all of them still at the
/// [opening] they were made with — the balances must have read the records.
void checkOverview(String what, Object? answer, {required int accounts, required int opening}) {
  final value = _answered<wire.ListAccountsResponse>(what, answer);
  _require(value.accounts.length == accounts, what, '${value.accounts.length} accounts');
  _require(
    value.accounts.every((a) => a.id.isNotEmpty && a.balances.length == 1),
    what,
    'an account without its one balance',
  );
  _require(
    value.accounts.any((a) => a.balances.single.amountMinor != Int64(opening)),
    what,
    'only opening balances',
  );
}

T _ok<T>(ZenResult<T> result) => switch (result) {
  ZenSuccess(:final data) => data,
  ZenFailure(:final error) => throw StateError('the store failed: ${error.message}'),
};

typedef _Populated = ({int records, int other, int accounts});

/// What every account opens with.
const _opening = 1000000;

/// A ledger of [size] records over the last six years in PLN: 85% expenses over 20 categories, the
/// rest income and refunds, in 4 accounts.
Future<_Populated> _populate(PrudentLocalStore store, Ledger ledger, int size) async {
  final random = Random(11);
  final categories = <String>[];
  for (var c = 0; c < 20; c++) {
    final made = _ok(
      await ledger.createCategory(
        wire.CreateCategoryRequest(title: 'Category $c', iconKey: 'food'),
      ),
    );
    categories.add(made.id);
  }
  final accounts = <String>[];
  for (var a = 0; a < 4; a++) {
    final made = _ok(
      await ledger.createAccount(
        wire.CreateAccountRequest(
          name: 'Account $a',
          type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(_opening))],
        ),
      ),
    );
    accounts.add(made.value.id);
  }
  final now = DateTime.now().toUtc();
  var expenses = 0;
  var other = 0;
  for (var from = 0; from < size; from += 500) {
    final batch = StoreBatch(store);
    for (var i = from; i < min(size, from + 500); i++) {
      final index = now.year * 12 + (now.month - 1) - random.nextInt(72);
      final year = index ~/ 12;
      final month = index % 12 + 1;
      final day = 1 + random.nextInt(28);
      final expense = random.nextInt(100) < 85;
      expense ? expenses++ : other++;
      batch.putRecord(
        Record(
          id: _id(i),
          title: 'Record $i',
          posting: Posting(
            accountId: accounts[random.nextInt(accounts.length)],
            currency: 'PLN',
            amountMinor: Int64((expense ? -1 : 1) * (1 + random.nextInt(300000))),
          ),
          date:
              '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
              '${day.toString().padLeft(2, '0')}',
          categoryId: categories[random.nextInt(categories.length)],
        ),
      );
    }
    _ok(await store.writeAll(batch));
  }
  return (records: expenses, other: other, accounts: accounts.length);
}

/// A Local id: 32 lower-case hex characters.
String _id(int i) => 'b' * 8 + i.toRadixString(16).padLeft(24, '0');
