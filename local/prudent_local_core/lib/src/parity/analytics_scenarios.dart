import 'dart:math';

import 'parity_scenario.dart';

/// Builds the large synthetic ledger of unit 7's parity run (ADR-118): thousands of records over
/// more than five years, many categories and several currencies, then every analytics question the
/// shared screens can ask, answered by the server and by Local and compared to the cent.
///
/// It is code, not a committed JSON file, for one reason: `spend-by-period` is relative to "now"
/// (UTC), so the dates of the ledger must be too — a month that is "the current one" today is not
/// next month. Everything else is fixed by [seed], so a failure repeats.
///
/// **What it exercises** — each record is one of: an expense (most), income, a refund (positive, in
/// a category, never netted), an expense on the first or last day of a month (boundaries), a
/// transfer between two accounts, or a balance correction (neither is spending). Some records are
/// then edited (amount, month, category and currency-preserving) and some deleted, so the figures
/// have to follow. The dates run from about 70 months back to the end of the current month, so the
/// trailing 60-month window has records on both sides of its edge, and a few records are decades old
/// so the year window's edge is crossed too.
///
/// **Currencies are reserved.** The server's analytics sum every record of its one user in a
/// currency, and the parity run shares one user across scenarios (ADR-107), so a scenario's figures
/// are its own only if nobody else uses its currencies: [currencies] are used by this generator
/// and by no committed scenario, and `analytics_scenarios_test.dart` fails if that stops being true.
abstract final class AnalyticsScenarios {
  /// The currencies of the large ledger; `analytics.json` reserves SEK, NOK and DKK for itself.
  static const currencies = ['CZK', 'HUF', 'ISK', 'RON'];

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
      for (final count in const [1, 2, 6, 12, 24, 59, 60]) {
        step('analytics.spendByPeriod', {
          'currency': currency,
          'granularity': 'MONTH',
          'count': count,
        });
      }
      for (final count in const [1, 2, 5, 10, 60]) {
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
}
