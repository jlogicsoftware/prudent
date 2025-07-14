import 'package:uuid/uuid.dart';

enum AccountType { cash, card, checking, savings }

class Account {
  final String id;
  final String name;
  final AccountType type;
  final double balance;
  final String currency;
  final bool isDefault;
  final bool isActive;
  final bool includeInTotal;
  final bool includeInOverview;
  final String? description;

  Account({
    required this.name,
    required this.type,
    required this.balance,
    required this.currency,
  }) : id = Uuid().v4(),
       isDefault = false,
       isActive = true,
       includeInTotal = true,
       includeInOverview = true,
       description = null;

  @override
  String toString() {
    return 'Account(id: $id, name: $name, balance: $balance, currency: $currency)';
  }
}
