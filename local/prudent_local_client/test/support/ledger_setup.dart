import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart' show Ledger;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';

/// The value of a ledger answer a test expects to succeed; the error, named, when it did not.
T ok<T>(ZenResult<T> result) => switch (result) {
  ZenSuccess(:final data) => data,
  ZenFailure(:final error) => throw StateError(
    'expected success: ${error.runtimeType} ${error.message}',
  ),
};

/// One account and one category, made on [on]. Synthetic values only.
typedef Books = ({String account, String category});

/// An account "Wallet" holding PLN 100.00 (in the overview and the totals) and a category "Food".
Future<Books> openBooks(
  Ledger on, {
  String name = 'Wallet',
  int openingMinor = 10000,
}) async {
  final account = ok(
    await on.createAccount(
      wire.CreateAccountRequest(
        name: name,
        type: wire.AccountType.ACCOUNT_TYPE_CASH,
        isActive: true,
        includeInTotal: true,
        includeInOverview: true,
        balances: [
          wire.CurrencyBalance(
            currency: 'PLN',
            amountMinor: Int64(openingMinor),
          ),
        ],
      ),
    ),
  ).value;
  final category = ok(
    await on.createCategory(
      wire.CreateCategoryRequest(title: 'Food', iconKey: 'food'),
    ),
  );
  return (account: account.id, category: category.id);
}

/// A PLN record on [books]' account.
Future<wire.Record> addRecord(
  Ledger on,
  Books books, {
  int amount = -1000,
  String title = 'Bread',
  String date = '2026-11-02',
}) async => ok(
  await on.createRecord(
    wire.CreateRecordRequest(
      title: title,
      amountMinor: Int64(amount),
      date: date,
      categoryId: books.category,
      accountId: books.account,
      currency: 'PLN',
    ),
  ),
);

/// The record [id] with a new [amount], everything else as [addRecord] made it.
Future<wire.Record> editAmount(
  Ledger on,
  Books books,
  String id,
  int amount, {
  String date = '2026-11-02',
}) async => ok(
  await on.updateRecord(
    id,
    wire.UpdateRecordRequest(
      title: 'Bread',
      amountMinor: Int64(amount),
      date: date,
      categoryId: books.category,
      accountId: books.account,
      currency: 'PLN',
    ),
  ),
);
