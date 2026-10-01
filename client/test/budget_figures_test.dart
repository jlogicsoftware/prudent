// The monthly budget overview's arithmetic (jlogicsoftware/prudent#63): which month is next, what
// percentage is used, and when a budget counts as overspent — kept pure so each edge is pinned
// without pumping a screen.
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/budget/budget_figures.dart';
import 'package:prudent/budget/budget_month.dart';
import 'package:prudent/generated/prudent/v1/budgets.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';

BudgetFigures _figures({
  int plan = 0,
  int actual = 0,
  int carryOver = 0,
  int? remaining,
}) => BudgetFigures(
  plan: Int64(plan),
  actual: Int64(actual),
  carryOver: Int64(carryOver),
  // The server's definition (budgets.proto): carry-over + plan - actual.
  remaining: Int64(remaining ?? carryOver + plan - actual),
);

void main() {
  group('BudgetMonth', () {
    test('formats as the zero-padded YYYY-MM the endpoint takes', () {
      expect(BudgetMonth(2026, 3).wire, '2026-03');
      expect(BudgetMonth(2026, 12).wire, '2026-12');
    });

    test('moves across a year boundary in both directions', () {
      expect(BudgetMonth(2026, 12).next.wire, '2027-01');
      expect(BudgetMonth(2026, 1).previous.wire, '2025-12');
    });

    test('has no day: of() ignores it and equal months are equal', () {
      expect(BudgetMonth.of(DateTime(2026, 10, 31)), BudgetMonth(2026, 10));
      expect(BudgetMonth.of(DateTime(2026, 10, 31)).hashCode, BudgetMonth(2026, 10).hashCode);
      expect(BudgetMonth(2026, 10), isNot(BudgetMonth(2026, 11)));
    });

    test('next and previous are inverses', () {
      final month = BudgetMonth(2026, 1);
      expect(month.next.previous, month);
      expect(month.previous.next, month);
    });
  });

  group('BudgetFigures.percentUsed', () {
    test('is the share of the plan spent', () {
      expect(_figures(plan: 20000, actual: 5000).percentUsed, 25);
    });

    test('rounds down, so a month that has not used its money never reads 100%', () {
      expect(_figures(plan: 10000, actual: 9999).percentUsed, 99);
    });

    test('exceeds 100 once overspent', () {
      expect(_figures(plan: 10000, actual: 15000).percentUsed, 150);
    });

    test('measures against what was available, carry-over included', () {
      // 100 plan + 100 carried in = 200 available; 100 spent is half of it.
      expect(_figures(plan: 10000, carryOver: 10000, actual: 10000).percentUsed, 50);
      // An overspend carried in shrinks what is available: 100 - 50 = 50, so 25 spent is half.
      expect(_figures(plan: 10000, carryOver: -5000, actual: 2500).percentUsed, 50);
    });

    test('is zero when nothing was spent or refunds outweigh spending', () {
      expect(_figures(plan: 10000, actual: 0).percentUsed, 0);
      expect(_figures(plan: 10000, actual: -2500).percentUsed, 0);
    });

    test('is null when the carry-over has consumed the whole plan', () {
      expect(_figures(plan: 10000, carryOver: -10000).percentUsed, isNull);
      expect(_figures(plan: 10000, carryOver: -25000, actual: 100).percentUsed, isNull);
    });

    test('does not overflow on large amounts', () {
      // 9e15 minor units is far past any real budget; the point is exact integer arithmetic.
      expect(
        BudgetFigures(
          plan: Int64.parseInt('9000000000000000'),
          actual: Int64.parseInt('4500000000000000'),
          carryOver: Int64.ZERO,
          remaining: Int64.parseInt('4500000000000000'),
        ).percentUsed,
        50,
      );
    });
  });

  group('BudgetFigures.isOverspent', () {
    test('is false while something remains, and at exactly zero', () {
      expect(_figures(plan: 10000, actual: 9999).isOverspent, isFalse);
      expect(_figures(plan: 10000, actual: 10000).isOverspent, isFalse);
      expect(_figures(plan: 10000, actual: 10000).overspentBy, Int64.ZERO);
    });

    test('is true past zero, and says by how much', () {
      final figures = _figures(plan: 10000, actual: 12550);
      expect(figures.isOverspent, isTrue);
      expect(figures.overspentBy, Int64(2550));
    });

    test('is true for an overspend carried in even when nothing was spent', () {
      final figures = _figures(plan: 10000, carryOver: -15000, actual: 0);
      expect(figures.isOverspent, isTrue);
      expect(figures.overspentBy, Int64(5000));
    });

    test('uses the server remaining rather than recomputing it', () {
      // Deliberately inconsistent inputs: the screen must show the server's figure.
      expect(_figures(plan: 10000, actual: 1000, remaining: -1).isOverspent, isTrue);
    });
  });

  group('BudgetFigures from the wire', () {
    test('ofItem and ofTotals read the matching fields', () {
      final item = CategoryBudgetSummary(
        planMinor: Int64(1),
        actualMinor: Int64(2),
        remainingMinor: Int64(3),
        carryOverMinor: Int64(4),
      );
      final summary = BudgetSummaryResponse(
        totalPlanMinor: Int64(10),
        totalActualMinor: Int64(20),
        totalRemainingMinor: Int64(30),
        totalCarryOverMinor: Int64(40),
      );

      final fromItem = BudgetFigures.ofItem(item);
      expect([fromItem.plan, fromItem.actual, fromItem.remaining, fromItem.carryOver], [
        Int64(1),
        Int64(2),
        Int64(3),
        Int64(4),
      ]);
      final fromTotals = BudgetFigures.ofTotals(summary);
      expect(
        [fromTotals.plan, fromTotals.actual, fromTotals.remaining, fromTotals.carryOver],
        [Int64(10), Int64(20), Int64(30), Int64(40)],
      );
    });
  });

  group('budgetItemsByTitle', () {
    CategoryBudgetSummary item(String id) => CategoryBudgetSummary(categoryId: id);

    test('orders by title, ignoring case, and does not touch the input', () {
      final categories = {
        'a': Category(id: 'a', title: 'travel'),
        'b': Category(id: 'b', title: 'Food'),
        'c': Category(id: 'c', title: 'Rent'),
      };
      final input = [item('a'), item('b'), item('c')];

      final ordered = budgetItemsByTitle(input, categories, 'Unknown');

      expect(ordered.map((i) => i.categoryId), ['b', 'c', 'a']);
      expect(input.map((i) => i.categoryId), ['a', 'b', 'c']);
    });

    test('files a category it cannot name under the unknown title, ties broken by id', () {
      final categories = {'b': Category(id: 'b', title: 'Food')};

      final ordered = budgetItemsByTitle([item('z'), item('b'), item('y')], categories, 'Unknown');

      expect(ordered.map((i) => i.categoryId), ['b', 'y', 'z']);
    });
  });
}
