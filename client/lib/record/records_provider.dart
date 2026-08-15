import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent/category/category_provider.dart';

import 'record.dart';

final List<Record> registeredRecords = [
  Record(
    title: 'Flutter Course',
    amount: 19.99,
    date: DateTime.now(),
    category: registeredCategories.first,
  ),
  Record(
    title: 'Cinema',
    amount: 15.69,
    date: DateTime.now(),
    category: registeredCategories.last,
  ),
];

/// Records held in memory, exactly as accounts and categories are.
///
/// **No network call belongs here.** The client talks to one server and it is ours, reached
/// through the framework's transport — a direct call to a third-party backend from this layer is
/// forbidden, and it is the rule most worth stating at the point of temptation because it fails
/// *silently*: an application pointed at someone else's backend renders, authenticates and passes
/// every test.
///
/// Prudent's server does not exist yet, so the seed list below is where records come from until it
/// does, which leaves all three providers consistent — accounts, categories and records are process
/// memory and are lost on restart. That is deliberately temporary. They are rewired together over
/// `ZenClient`, at which point the seeds become server data created on first login and identity is
/// minted server-side rather than by the constructors here.
///
/// See `docs/DECISIONS.md` ADR-004.
class RecordsNotifier extends AsyncNotifier<List<Record>> {
  @override
  Future<List<Record>> build() async {
    // A copy, not the seed itself: the mutators below rebuild `state` from it, and handing out the
    // module-level list would let an edit in one session leak into the next `build()`.
    return List<Record>.of(registeredRecords);
  }

  void addRecord(Record record) {
    state = AsyncValue.data([...state.value!, record]);
  }

  void removeRecord(Record record) {
    state = AsyncValue.data(state.value!.where((r) => r != record).toList());
  }

  void editRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state.value!);
    updatedRecords[index] = record;
    state = AsyncValue.data(updatedRecords);
  }

  void insertRecord(int index, Record record) {
    final updatedRecords = List<Record>.from(state.value!);
    updatedRecords.insert(index, record);
    state = AsyncValue.data(updatedRecords);
  }
}

final recordsProvider = AsyncNotifierProvider<RecordsNotifier, List<Record>>(
  () => RecordsNotifier(),
);
