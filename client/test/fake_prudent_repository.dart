import 'package:flutter_test/flutter_test.dart';
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart';
import 'package:prudent_ui/prudent_repository.dart';
import 'package:zen_core/zen_core.dart';

/// A [PrudentRepository] that answers from memory, for tests that run a screen without any
/// transport (jlogicsoftware/prudent#245, unit 1). It holds categories only — the first thing a
/// test needed — and every other method is the framework's [Fake] behaviour: it throws, so a screen
/// that reaches for data the fake was not given fails loudly instead of reading an empty answer.
/// Add a collection here when a test needs one; do not make a method answer with a made-up value.
class FakePrudentRepository extends Fake implements PrudentRepository {
  FakePrudentRepository({List<Category> categories = const []})
    : categories = [...categories];

  final List<Category> categories;

  /// When set, [listCategories] answers with this failure instead of the list.
  ZenError? listCategoriesFailure;

  int listCategoriesCalls = 0;

  @override
  Future<ZenResult<ListCategoriesResponse>> listCategories() async {
    listCategoriesCalls++;
    final failure = listCategoriesFailure;
    if (failure != null) return ZenFailure(failure);
    return ZenSuccess(ListCategoriesResponse(categories: categories));
  }
}
