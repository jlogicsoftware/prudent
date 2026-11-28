import 'dart:math';

import 'parity_scenario.dart';

/// Builds the large synthetic ledger of unit 7's parity run (ADR-118): thousands of records over
/// more than five years, many categories and several currencies, then every analytics question the
/// shared screens can ask, answered by the server and by Local and compared to the cent.
///
/// It is code, not a committed JSON file, for one reason: `spend-by-period` is relative to "now"
/// (UTC), so the dates of the ledger must be too — a month that is "the current one" today is not
/// next month. **So the run is deterministic only while the date it is relative to stands**: the same
/// [seed] on the same UTC day builds the same ledger and a failure repeats, and nothing promises that
/// a later date builds it again. (What is read of the date today is its year and month.)
///
/// **What it exercises** — each record is one of: an expense (most), income, a refund (positive, in
/// a category, never netted), an expense on the first or last day of a month (boundaries), a
/// transfer between two accounts, or a balance correction (neither is spending). Some records are
/// then edited (amount, month, category and currency-preserving) and some deleted, so the figures
/// have to follow. The dates run from about 70 months back to the end of the current month, and a
/// few records are decades old.
///
/// **Both sides of every window's edge hold spend, whatever the seed drew**: for each trailing window
/// asked ([monthCounts], [yearCounts]) and each currency, one expense on the first day inside it and
/// one on the last day before it, written after the edits and deletes and touched by neither. And
/// every question has something to compare: [shortfall] says when an answer does not.
///
/// **Currencies are reserved.** The server's analytics sum every record of its one user in a
/// currency, and the parity run shares one user across scenarios (ADR-107), so a scenario's figures
/// are its own only if nobody else uses its currencies: [currencies] are used by this generator
/// and by no committed scenario, and `scenarios_test.dart` fails if that stops being true.
abstract final class AnalyticsScenarios {
  /// The currencies of the large ledger; `analytics.json` reserves THB, TRY and ILS for itself.
  static const currencies = ['CAD', 'NZD', 'SGD', 'HKD'];

  /// The `count`s asked of spend by month; the largest is the contract's largest.
  static const monthCounts = [1, 2, 6, 12, 24, 59, 60];

  /// The `count`s asked of spend by year.
  static const yearCounts = [1, 2, 5, 10, 60];

  /// A ledger of about [records] records, relative to [today] (read in UTC).
  static ParityScenario large({required DateTime today, int records = 4000, int seed = 20261116}) {
    final random = Random(seed);
    final now = today.toUtc();
    final steps = <ParityStep>[];
    void step(String op, Map<String, Object?> input, {String? as, String outcome = 'accepted'}) =>
        steps.add(ParityStep(op: op, input: input, bindAs: as, outcome: outcome));

    const categoryCount = 14;
    for (var c = 0; c < categoryCount; c++) {
      step('category.create', {'title': 'Category ${c + 1}', 'iconKey': 'food'}, as: 'cat$c');
    }
    const accountCount = 3;
    for (var a = 0; a < accountCount; a++) {
      step('account.create', {
        'name': 'Account ${a + 1}',
        'type': 'ACCOUNT_TYPE_CHECKING',
        'balances': [
          for (final currency in currencies) {'currency': currency, 'amountMinor': '1000000'},
        ],
      }, as: 'acc$a');
    }

    // A month back from "now": index 0 is the current month, 69 is about five years and ten months
    // earlier. A day is always valid in its month.
    String date(int monthsBack, {int? day}) {
      final index = now.year * 12 + (now.month - 1) - monthsBack;
      final year = index ~/ 12;
      final month = index % 12 + 1;
      final last = DateTime.utc(year, month + 1, 0).day;
      final d = day == null ? 1 + random.nextInt(last) : (day < 0 ? last : day);
      return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
          '${d.toString().padLeft(2, '0')}';
    }

    String amount(int ceiling) => '${1 + random.nextInt(ceiling)}';
    String pick(List<String> of) => of[random.nextInt(of.length)];
    final accounts = [
      for (var a = 0; a < accountCount; a++)
        r'$acc'
            '$a',
    ];
    final categories = [
      for (var c = 0; c < categoryCount; c++)
        r'$cat'
            '$c',
    ];

    final editable = <String>[];
    final deletable = <String>[];
    var recordNumber = 0;
    for (var i = 0; i < records; i++) {
      final currency = pick(currencies);
      final kind = random.nextInt(100);
      final monthsBack = random.nextInt(100) < 3 ? 70 + random.nextInt(200) : random.nextInt(70);
      if (kind < 3) {
        // A transfer between two accounts in one currency: not spending.
        final from = random.nextInt(accountCount);
        final to = (from + 1 + random.nextInt(accountCount - 1)) % accountCount;
        final value = amount(500000);
        step('transfer.create', {
          'title': 'Move $i',
          'fromAccount': accounts[from],
          'toAccount': accounts[to],
          'fromAmountMinor': value,
          'fromCurrency': currency,
          'toAmountMinor': value,
          'toCurrency': currency,
          'date': date(monthsBack),
        });
        continue;
      }
      if (kind < 4) {
        // A correction: its target is a fresh figure far from any real balance, so its delta is
        // large and never zero.
        step('correction.create', {
          'account': pick(accounts),
          'currency': currency,
          'balanceMinor': '${-5000000 - random.nextInt(1000000) - i * 7}',
          'date': date(monthsBack),
        });
        continue;
      }
      final sign = switch (kind) {
        < 19 => 1, // income and refunds
        _ => -1,
      };
      final boundary = random.nextInt(100) < 12;
      final day = boundary ? (random.nextBool() ? 1 : -1) : null;
      final magnitude = switch (random.nextInt(10)) {
        0 => 3,
        < 3 => 100000000, // large sums, to carry real cents through many additions
        _ => 200000,
      };
      final name = 'r${recordNumber++}';
      final tracked = random.nextInt(100) < 8;
      step('record.create', {
        'account': pick(accounts),
        'category': pick(categories),
        'amountMinor': '${sign * (1 + random.nextInt(magnitude))}',
        'currency': currency,
        'date': date(monthsBack, day: day),
        'title': 'Record $i',
      }, as: tracked ? name : null);
      if (tracked) (sign < 0 ? editable : deletable).add(name);
    }

    // Edits: the amount, the month and the category change, so the spend has to move.
    for (final name in editable.take(editable.length ~/ 2)) {
      step('record.update', {
        'record': '\$$name',
        'account': pick(accounts),
        'category': pick(categories),
        'amountMinor': '-${amount(300000)}',
        'currency': pick(currencies),
        'date': date(random.nextInt(70)),
        'title': 'Edited $name',
      });
    }
    // Deletes: a mix of spend and income.
    for (final name in [...deletable, ...editable.skip(editable.length ~/ 2)]) {
      step('record.delete', {'record': '\$$name'});
    }

    // The two days next to each window's edge (see the class comment). The amounts differ, so a day
    // wrongly in or out changes a figure by an amount that names it.
    var edge = 0;
    void spendOn(String currency, String day) => step('record.create', {
      'account': accounts.first,
      'category': categories.first,
      'amountMinor': '-${100000000 + ++edge}',
      'currency': currency,
      'date': day,
      'title': 'Edge $edge',
    });
    String year(int yearsBack) => (now.year - yearsBack).toString().padLeft(4, '0');
    for (final currency in currencies) {
      for (final count in monthCounts) {
        spendOn(currency, date(count - 1, day: 1));
        spendOn(currency, date(count, day: -1));
      }
      for (final count in yearCounts) {
        spendOn(currency, '${year(count - 1)}-01-01');
        spendOn(currency, '${year(count)}-12-31');
      }
    }

    // The questions the screens ask: the whole of each recent year and a few months by category;
    // the trailing windows by month and by year.
    for (final currency in currencies) {
      for (var yearsBack = 0; yearsBack < 4; yearsBack++) {
        step('analytics.spendByCategory', {'currency': currency, 'year': now.year - yearsBack});
      }
      for (final monthsBack in const [0, 1, 11, 23, 47, 59, 60, 69]) {
        final index = now.year * 12 + (now.month - 1) - monthsBack;
        step('analytics.spendByCategory', {
          'currency': currency,
          'year': index ~/ 12,
          'month': index % 12 + 1,
        });
      }
      for (final count in monthCounts) {
        step('analytics.spendByPeriod', {
          'currency': currency,
          'granularity': 'MONTH',
          'count': count,
        });
      }
      for (final count in yearCounts) {
        step('analytics.spendByPeriod', {
          'currency': currency,
          'granularity': 'YEAR',
          'count': count,
        });
      }
    }

    return ParityScenario(
      name: 'analytics_large',
      description:
          'A synthetic ledger of $records operations over about six years in ${currencies.length} '
          'currencies, edited and deleted in part, then every analytics question compared to the '
          'cent (unit 7, ADR-118).',
      rules: const ['7.1', '7.2', '7.3'],
      steps: steps,
    );
  }

  /// What the answer to one of this ledger's analytics questions lacks, or null. Two empty answers
  /// agree, so a parity run says nothing unless the figures it compared are there: every question
  /// must be accepted with at least one figure, none of them zero, and a trailing window must reach
  /// exactly from the oldest bucket inside it to the one that holds [today].
  static String? shortfall(
    String op,
    Map<String, Object?> input,
    Map<String, Object?> observation, {
    required DateTime today,
  }) {
    final asked = '$op $input';
    if (observation['outcome'] != 'accepted') return '$asked was not accepted: $observation';
    final byPeriod = op == 'analytics.spendByPeriod';
    final figures = observation[byPeriod ? 'periods' : 'items'];
    if (figures is! Map || figures.isEmpty) return '$asked answered no figure.';
    if (figures.values.any((amount) => amount == '0')) return '$asked answered a zero figure.';
    if (!byPeriod) return null;
    final now = today.toUtc();
    final count = input['count']! as int;
    final monthly = input['granularity'] == 'MONTH';
    String label(int back) {
      if (!monthly) return (now.year - back).toString().padLeft(4, '0');
      final month = DateTime.utc(now.year, now.month - back);
      return '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    }

    final periods = figures.keys.cast<String>().toList()..sort();
    if (periods.first != label(count - 1) || periods.last != label(0)) {
      return '$asked answered ${periods.first} to ${periods.last}, '
          'not ${label(count - 1)} to ${label(0)}.';
    }
    return null;
  }
}
