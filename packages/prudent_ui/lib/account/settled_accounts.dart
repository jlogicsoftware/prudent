import 'package:meta/meta.dart' show immutable;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart';

/// The accounts, and — by account — what their balances leave out because two of the person's
/// devices disagree about it (Prudent Local, ADR-113).
///
/// The wire `Account.balances` has no room to say "this figure leaves out a record two devices
/// disagree about", and a balance that silently drops money reads as settled. So the list of
/// accounts carries the caveat with it: a screen that shows a balance reads both from one answer,
/// and cannot show the figure without passing the place where its caveat sits.
///
/// The server holds one copy of the ledger, so every figure it answers is settled and
/// [unsettled] is empty there. Prudent Local leaves a disputed record, transfer or opening out of
/// every figure until the person settles it, and names it here.
@immutable
final class SettledAccounts {
  /// The accounts, as the repository answered them.
  final List<Account> accounts;

  /// By account id, the ids of what that account's balances leave out, sorted. An account whose
  /// figures are all settled is absent.
  final Map<String, List<String>> unsettled;

  const SettledAccounts(this.accounts, [this.unsettled = const {}]);

  /// How many entries the balances of [accountId] leave out; zero when they are settled.
  int leftOutOf(String accountId) => unsettled[accountId]?.length ?? 0;
}
