import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account.dart';

final List<Account> registeredAccounts = [
  Account(
    name: 'Master Card',
    type: AccountType.card,
    balance: 1500.00,
    currency: 'USD',
  ),
  Account(
    name: 'Cash',
    type: AccountType.cash,
    balance: 300.00,
    currency: 'USD',
  ),
];

class AccountNotifier extends Notifier<List<Account>> {
  @override
  List<Account> build() {
    return registeredAccounts;
  }

  void addAccount(Account account) {
    state = [...state, account];
  }

  void removeAccount(Account account) {
    state = state.where((a) => a != account).toList();
  }

  void editAccount(int index, Account account) {
    final updatedAccounts = List<Account>.from(state);
    updatedAccounts[index] = account;
    state = updatedAccounts;
  }

  void insertAccount(int index, Account account) {
    final updatedAccounts = List<Account>.from(state);
    updatedAccounts.insert(index, account);
    state = updatedAccounts;
  }

  double totalBalance() {
    return state.fold(
      0.0,
      (sum, account) =>
          account.isActive && account.includeInTotal
              ? sum + account.balance
              : sum,
    );
  }
}

final accountProvider = NotifierProvider<AccountNotifier, List<Account>>(
  () => AccountNotifier(),
);
