import '../generated/prudent/v1/categories.pb.dart';

/// The categories a form may offer for a record (M3, jlogicsoftware/prudent#62, ADR-047).
///
/// An archived category is retired: the server refuses a new record in it, so offering it would
/// only lead to a refusal. The one exception is [keep] — the category the record being edited
/// already has. A dropdown whose value is not among its items fails to build, and the user editing
/// an old record must see the category it is filed under; the server accepts the edit as long as
/// the category does not change.
///
/// Lists, filters and history screens do not use this: they show every category, archived or not,
/// because a record's category must stay readable.
///
/// [expense] narrows the list to the direction of the record being written (jlogicsoftware/prudent#229):
/// an expense is offered the expense categories, income the income ones, and a category with no kind
/// (one that predates the field) serves both. Null offers every kind.
List<Category> selectableCategories(List<Category> all, {String? keep, bool? expense}) => [
  for (final category in all)
    if ((!category.archived && _suits(category, expense)) || category.id == keep) category,
];

bool _suits(Category category, bool? expense) {
  if (expense == null) return true;
  return switch (category.kind) {
    CategoryKind.CATEGORY_KIND_EXPENSE => expense,
    CategoryKind.CATEGORY_KIND_INCOME => !expense,
    _ => true,
  };
}
