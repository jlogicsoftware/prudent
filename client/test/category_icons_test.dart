// An unknown icon_key renders the documented fallback instead of throwing (Phase 3 test list;
// proto/prudent/v1/categories.proto: "a category created by a newer client must not break an
// older one").
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/category/category_icons.dart';

void main() {
  test('a known key resolves to its icon', () {
    expect(prudentIconFor('work'), prudentCategoryIcons['work']);
  });

  test('an unknown key renders the documented fallback rather than throwing', () {
    expect(() => prudentIconFor('some-key-a-newer-client-invented'), returnsNormally);
    expect(prudentIconFor('some-key-a-newer-client-invented'), prudentUnknownCategoryIcon);
  });

  test('an empty key also falls back rather than throwing', () {
    expect(prudentIconFor(''), prudentUnknownCategoryIcon);
  });
}
