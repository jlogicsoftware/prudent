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
List<Category> selectableCategories(List<Category> all, {String? keep}) => [
  for (final category in all)
    if (!category.archived || category.id == keep) category,
];
