/// How long the analytics screen and the overview take at the size of a real ledger (unit 7,
/// ADR-118). Pure Dart: `dart run tool/analytics_benchmark.dart` on the VM, and the same
/// [runAnalyticsBenchmark] inside a throwaway Flutter app on a device or emulator (unit 12 is the
/// release gate that must run it on a real device).
///
/// The ledger is built the quick way — accounts and categories through the [Ledger], records
/// written in batches straight to the store — because building 50 000 records one `createRecord` at
/// a time is quadratic and measures the write path, which is not what is asked. What is timed is
/// the READ: the questions the screens ask. Every figure is a median of [repeats] runs after one
/// warm-up run, and the first (cold) run is reported too.
///
/// Synthetic data only: a seeded random ledger, nothing real.
library;

import 'dart:io';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
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
      final questions = <String, Future<Object?> Function()>{
        'spend by category, one year': () =>
            analytics.spendByCategory(currency: 'PLN', year: year - 1),
        'spend by category, one month': () =>
            analytics.spendByCategory(currency: 'PLN', year: year - 1, month: 6),
        'spend by month, last 12': () =>
            analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 12),
        'spend by month, last 60': () =>
            analytics.spendByPeriod(currency: 'PLN', granularity: 'MONTH', count: 60),
        'spend by year, last 5': () =>
            analytics.spendByPeriod(currency: 'PLN', granularity: 'YEAR', count: 5),
        'overview: every account with its balances': () => ledger.listAccounts(),
      };
      for (final MapEntry(:key, :value) in questions.entries) {
        final cold = Stopwatch()..start();
        _check(key, await value());
        final coldMs = cold.elapsedMicroseconds / 1000;
        final times = <double>[];
        for (var i = 0; i < repeats; i++) {
          final run = Stopwatch()..start();
          _check(key, await value());
          times.add(run.elapsedMicroseconds / 1000);
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

void _check(String what, Object? answer) {
  if (answer is ZenFailure) throw StateError('$what failed: ${answer.error}');
}

T _ok<T>(ZenResult<T> result) => switch (result) {
  ZenSuccess(:final data) => data,
  ZenFailure(:final error) => throw StateError('the store failed: ${error.message}'),
};

typedef _Populated = ({int records, int other, int accounts});

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
          balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(1000000))],
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
