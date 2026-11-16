import '../account_numbers.dart';
import '../civil_date.dart';
import '../currencies.dart';
import '../currency_totals.dart';
import '../minor_units.dart';
import '../refusal.dart';
import '../text_rules.dart';
import 'parity_backend.dart';

/// The local side of the parity harness for unit 3: the operations the first scenarios use, run
/// through this package's rules over a small in-memory model.
///
/// **What it is not.** It is not Prudent Local's repository — that is unit 4's store and unit 5's
/// ledger, which will register the same operation names on a store-backed backend and replace this
/// one; the scenarios and the engine stay as they are. Until then this backend enforces **only the
/// unit-3 rules** (money, currencies, account numbers, dates, months, text) plus the bare minimum to
/// hold a scenario together (an account's currencies, so a record knows its balance). Any other
/// rule the server enforces is simply absent here, so a scenario that trips one shows up as a
/// difference — server refused, local accepted — never as a silent pass. That is why every setup
/// step in a scenario states `"outcome": "accepted"`.
///
/// Inputs use the wire's JSON field names; `"$name"` references stand for ids bound with `as`.
final class LocalRulesBackend extends ParityBackend {
  @override
  String get name => 'local';

  final Map<String, _Account> _accounts = {};
  final Set<String> _categories = {};
  final Set<String> _liveResets = {};
  int _nextId = 0;

  @override
  late final Map<String, ParityOp> ops = {
    'account.create': _guarded(_createAccount),
    'account.balances': _guarded(_balances),
    'category.create': _guarded(_createCategory),
    'record.create': _guarded(_createRecord),
    'budget.set': _guarded(_setBudget),
    'reset.create': _guarded(_createReset),
  };

  @override
  Future<void> open(String scenarioName) async {
    _accounts.clear();
    _categories.clear();
    _liveResets.clear();
    _nextId = 0;
  }

  @override
  Future<void> close() async {}

  /// The proto's `AccountType` names a create may carry; `ACCOUNT_TYPE_UNSPECIFIED` is what an
  /// omitted field decodes to and is refused, as on the server (`AccountResource.java:262`).
  static const _accountTypes = {
    'ACCOUNT_TYPE_CASH',
    'ACCOUNT_TYPE_CARD',
    'ACCOUNT_TYPE_CHECKING',
    'ACCOUNT_TYPE_SAVINGS',
  };

  /// A [Refusal] becomes the refused observation; anything else is a bug in a rule or a scenario
  /// and propagates, so the engine fails the step instead of comparing it.
  ParityOp _guarded(Future<StepResult> Function(Map<String, Object?>, ParityBindings) op) =>
      (input, bindings) async {
        try {
          return await op(input, bindings);
        } on Refusal catch (refusal) {
          return StepResult(ParityObservation.refused(refusal.status));
        }
      };

  String _mint() => (++_nextId).toRadixString(16).padLeft(32, '0');

  Future<StepResult> _createAccount(Map<String, Object?> input, ParityBindings bindings) async {
    final name = TextRules.requiredTrimmed(_text(input, 'name'), rule: '3.7');
    if (!_accountTypes.contains(input['type'])) {
      throw const Refusal.invalid('5', 'An account needs a type.');
    }
    final balances = (input['balances'] as List<Object?>?) ?? const [];
    if (balances.isEmpty) {
      throw const Refusal.invalid('5', 'An account must hold at least one currency.');
    }
    final account = _Account();
    for (final balance in balances.cast<Map<String, Object?>>()) {
      final currency = Currencies.parse(_text(balance, 'currency'));
      if (account.openings.holds(currency)) {
        // "pln" and "PLN" are one currency once normalised: refused, never merged (rule 3.2).
        throw const Refusal.invalid('3.2', 'A currency appears twice in this account.');
      }
      account.openings.add(currency, _amount(balance, 'amountMinor'));
    }
    final number = AccountNumbers.normalize(_text(input, 'accountNumber'));
    if (number != null && _accounts.values.any((other) => other.number == number)) {
      // Two spellings of one number are one number (ADR-090): the second is a conflict.
      throw const Refusal.conflict('3.6', 'Another account already has this account number.');
    }
    account.number = number;
    final id = _mint();
    _accounts[id] = account;
    return StepResult(
      ParityObservation.accepted({
        'name': name,
        'balances': _figures(account.openings),
        'accountNumber': number ?? '',
      }),
      createdId: id,
    );
  }

  Future<StepResult> _balances(Map<String, Object?> input, ParityBindings bindings) async {
    final account = _accounts[bindings.resolve(input['account'])]!;
    final totals = CurrencyTotals();
    for (final currency in account.openings.currencies) {
      totals.add(currency, addExact(account.openings.of(currency), account.records.of(currency)));
    }
    return StepResult(ParityObservation.accepted({'balances': _figures(totals)}));
  }

  Future<StepResult> _createCategory(Map<String, Object?> input, ParityBindings bindings) async {
    TextRules.requiredTrimmed(_text(input, 'title'), rule: '3.7');
    final id = _mint();
    _categories.add(id);
    return StepResult(ParityObservation.accepted(), createdId: id);
  }

  /// The order of `RecordWriter.apply`: title, amount, account, category, currency, the account
  /// holding it, date.
  Future<StepResult> _createRecord(Map<String, Object?> input, ParityBindings bindings) async {
    final title = TextRules.requiredTrimmed(_text(input, 'title'), rule: '3.7');
    final amount = _amount(input, 'amountMinor');
    if (amount == 0) {
      throw const Refusal.invalid('3.1', 'A record needs a nonzero amount.');
    }
    final account = _accounts[bindings.resolve(input['account'])]!;
    if (!_categories.contains(bindings.resolve(input['category']))) {
      throw StateError('record.create names a category no step created');
    }
    final currency = Currencies.parse(_text(input, 'currency'));
    if (!account.openings.holds(currency)) {
      throw const Refusal.invalid('3.2', 'The account does not hold this currency.');
    }
    final date = CivilDate.parse(_text(input, 'date'));
    account.records.add(currency, amount);
    return StepResult(
      ParityObservation.accepted({
        'title': title,
        'amountMinor': ParityObservation.figure(amount),
        'currency': currency,
        'date': date.toString(),
        'payee': TextRules.optionalTrimmed(_text(input, 'payee')),
        'note': TextRules.optionalTrimmed(_text(input, 'note')),
      }),
      createdId: _mint(),
    );
  }

  /// The order of `BudgetResource.set`: category, month, currency, then a positive amount.
  Future<StepResult> _setBudget(Map<String, Object?> input, ParityBindings bindings) async {
    _category(input, bindings);
    final month = CivilMonth.parse(_text(input, 'month'));
    final currency = Currencies.parse(_text(input, 'currency'));
    final amount = _amount(input, 'amountMinor');
    if (amount <= 0) {
      throw const Refusal.invalid('6', 'A budget needs a positive amount.');
    }
    return StepResult(
      ParityObservation.accepted({
        'month': month.toString(),
        'currency': currency,
        'amountMinor': ParityObservation.figure(amount),
      }),
    );
  }

  /// The order of `BudgetCarryOverResetResource.reset`: category, month, currency, note. The
  /// discarded carry-over is unit 6a's calculation and is not observed until that unit adds it.
  Future<StepResult> _createReset(Map<String, Object?> input, ParityBindings bindings) async {
    final category = _category(input, bindings);
    final month = CivilMonth.parse(_text(input, 'month'));
    final currency = Currencies.parse(_text(input, 'currency'));
    final note = TextRules.strippedNote(_text(input, 'note') ?? '');
    if (!_liveResets.add('$category|$month|$currency')) {
      throw const Refusal.conflict('6', 'This slot already has a live reset.');
    }
    return StepResult(
      ParityObservation.accepted({'month': month.toString(), 'currency': currency, 'note': note}),
      createdId: _mint(),
    );
  }

  String _category(Map<String, Object?> input, ParityBindings bindings) {
    final id = bindings.resolve(input['category']);
    if (!_categories.contains(id)) {
      throw StateError('no step created category ${input['category']}');
    }
    return id;
  }

  static Map<String, String> _figures(CurrencyTotals totals) => {
    for (final entry in totals.asMap().entries) entry.key: ParityObservation.figure(entry.value),
  };

  static String? _text(Map<String, Object?> input, String key) {
    final value = input[key];
    if (value != null && value is! String) throw FormatException('"$key" is text.');
    return value as String?;
  }

  /// An amount as proto3 JSON carries it: a decimal string, parsed as a signed 64-bit integer the
  /// way the server's JSON reader does (`"-0"` is zero).
  static int _amount(Map<String, Object?> input, String key) {
    final value = input[key];
    if (value is! String) throw FormatException('"$key" is a string of minor units.');
    return int.parse(value);
  }
}

final class _Account {
  final CurrencyTotals openings = CurrencyTotals();
  final CurrencyTotals records = CurrencyTotals();
  String? number;
}
