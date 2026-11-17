import 'package:meta/meta.dart' show immutable;

/// A calculated answer — a budget summary, free money, goal progress — together with how many
/// entries its figures leave out because two of the person's devices disagree about them (Prudent
/// Local, ADR-113, ADR-116). As with [SettledAccounts], the caveat travels in the same answer as
/// the figures, so a screen cannot show one without the other. The server holds one copy of the
/// ledger, so its answers always leave out nothing.
@immutable
final class SettledFigures<T> {
  /// The answer, its figures computed from settled values only.
  final T value;

  /// How many distinct records, budgets, resets or allocations the figures leave out.
  final int leftOut;

  const SettledFigures(this.value, [this.leftOut = 0]);
}
