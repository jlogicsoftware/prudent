import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:zen_core/zen_core.dart';

import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';

/// Two or more accounts with one account number.
///
/// An account number is unique per person (ADR-090; a unique index, `account_number.sql:27`, phase-0
/// §0.3 row 5.9): it is what an imported statement is matched to. Two devices can each give the number
/// to a different account, so the person clears it on all but one. The issue names the accounts by id
/// only; the number itself never enters an issue's id or facts.
final class DuplicateAccountNumberCheck implements IntegrityCheck {
  const DuplicateAccountNumberCheck();

  @override
  String get name => 'duplicate_account_number';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final byNumber = <String, List<String>>{};
    for (final account in snapshot.accounts.values) {
      if (account.accountNumber.isEmpty) continue;
      byNumber.putIfAbsent(account.accountNumber, () => []).add(account.id);
    }
    for (final ids in byNumber.values) {
      if (ids.length < 2) continue;
      ids.sort();
      yield IntegrityIssue(
        code: 'account.number_duplicate',
        collection: 'accounts',
        recordId: ids.first,
        key: ids.join('+'),
        facts: {'accountIds': ids.join(',')},
        actions: [
          IntegrityAction.choose('clear_account_number', ids, (id) {
            return switch (store.accounts.get(id)) {
              ZenSuccess(:final data) => store.putAccount(data.deepCopy()..clearAccountNumber()),
              ZenFailure(:final error) => Future.value(ZenResult.err(error)),
            };
          }),
        ],
      );
    }
  }
}
