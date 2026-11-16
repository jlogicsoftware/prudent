import 'package:zen_core/zen_core.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../derived_ids.dart';
import '../../prudent_local_store.dart';
import '../../write_expect.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';
import 'repairs.dart';

/// The settings name a default account that is no longer in the store.
///
/// The default is one field of the settings record (ADR-102), so two devices can never leave two
/// defaults; but one device can delete the account while another makes it the default. The person
/// picks another default or clears it.
final class DefaultAccountCheck implements IntegrityCheck {
  const DefaultAccountCheck();

  @override
  String get name => 'default_account';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final settings = snapshot.settings;
    if (settings == null || !settings.hasDefaultAccountId()) return;
    final missing = settings.defaultAccountId;
    if (snapshot.accounts.containsKey(missing)) return;
    final choices = Repairs.activeAccounts(snapshot).toList()..sort();
    yield IntegrityIssue(
      code: 'reference.default_account_missing',
      collection: 'settings',
      recordId: settings.id,
      facts: {'accountId': missing},
      actions: [
        IntegrityAction.now(
          'clear_default_account',
          () => _edit(store, (s) => s.clearDefaultAccountId()),
        ),
        if (choices.isNotEmpty)
          IntegrityAction.choose(
            'choose_default_account',
            choices,
            (id) => _edit(store, (s) => s.defaultAccountId = id),
          ),
      ],
    );
  }

  /// Edits the settings as they stand when the person acts.
  static Future<ZenResult<Object?>> _edit(
    PrudentLocalStore store,
    void Function(Settings settings) change,
  ) {
    switch (store.settings.get(DerivedIds.settings)) {
      case ZenSuccess(:final data):
        final next = data.deepCopy();
        change(next);
        return store.putSettings(next, expect: WriteExpects.asRead(data));
      case ZenFailure(:final error):
        return Future.value(ZenResult.err(error));
    }
  }
}
