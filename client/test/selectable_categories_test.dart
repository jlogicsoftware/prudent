// Which categories a record form offers (M3, jlogicsoftware/prudent#62, ADR-047).
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/category/selectable_categories.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';

Category _category(String id, {bool archived = false}) =>
    Category(id: id, title: id, archived: archived);

void main() {
  final all = [
    _category('food'),
    _category('old', archived: true),
    _category('rent'),
  ];

  test('an archived category is not offered for a new record', () {
    expect(selectableCategories(all).map((c) => c.id), ['food', 'rent']);
  });

  test('the category a record already has is kept, even archived', () {
    // A dropdown whose value is not among its items fails to build, and the server accepts an edit
    // that leaves the category unchanged.
    expect(selectableCategories(all, keep: 'old').map((c) => c.id), [
      'food',
      'old',
      'rent',
    ]);
  });

  test('keeping an active category changes nothing', () {
    expect(selectableCategories(all, keep: 'food').map((c) => c.id), [
      'food',
      'rent',
    ]);
  });

  test('an unknown keep id does not invent a category', () {
    expect(selectableCategories(all, keep: 'gone').map((c) => c.id), [
      'food',
      'rent',
    ]);
  });
}
