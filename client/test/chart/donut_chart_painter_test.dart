// The chart renders with zero, one and many categories — the shapes a pie/donut chart typically
// throws on (docs/prudent-migration-plan.md Phase 4 test list).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/chart/donut_chart_painter.dart';

Future<void> _pump(WidgetTester tester, List<DonutSlice> slices) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 200,
        height: 200,
        child: CustomPaint(painter: DonutChartPainter(slices: slices, trackColor: Colors.grey)),
      ),
    ),
  ),
);

void main() {
  testWidgets('zero categories: an empty slice list renders without throwing', (tester) async {
    await _pump(tester, const []);
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('one category: a single slice renders a full ring without throwing', (tester) async {
    await _pump(tester, const [DonutSlice(value: 100, color: Colors.blue)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many categories: several slices render without throwing', (tester) async {
    await _pump(tester, const [
      DonutSlice(value: 50, color: Colors.blue),
      DonutSlice(value: 30, color: Colors.red),
      DonutSlice(value: 20, color: Colors.green),
      DonutSlice(value: 10, color: Colors.orange),
      DonutSlice(value: 5, color: Colors.purple),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slice with value zero does not crash the total', (tester) async {
    await _pump(tester, const [
      DonutSlice(value: 0, color: Colors.blue),
      DonutSlice(value: 10, color: Colors.red),
    ]);
    expect(tester.takeException(), isNull);
  });

  test('shouldRepaint is false when neither slices nor track colour changed', () {
    final slices = [const DonutSlice(value: 1, color: Colors.blue)];
    final a = DonutChartPainter(slices: slices, trackColor: Colors.grey);
    final b = DonutChartPainter(slices: slices, trackColor: Colors.grey);
    expect(a.shouldRepaint(b), isFalse);
  });

  test('shouldRepaint is true when the slice list instance changed', () {
    const a = DonutChartPainter(slices: [DonutSlice(value: 1, color: Colors.blue)], trackColor: Colors.grey);
    const b = DonutChartPainter(slices: [DonutSlice(value: 2, color: Colors.blue)], trackColor: Colors.grey);
    expect(a.shouldRepaint(b), isTrue);
  });
}
