import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;

import 'two_devices.dart';

/// The instant every plan test reckons as now unless it says otherwise: noon UTC on a Monday.
final DateTime noon = DateTime.utc(2026, 11, 16, 12);

/// An account holding PLN 1000.00 and EUR 50.00, and an expense category, made through [ledger].
Future<({String account, String category})> planWorld(Ledger ledger) async {
  final account = Device.ok(
    await ledger.createAccount(
      wire.CreateAccountRequest(
        name: 'Main',
        type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
        balances: [
          wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64(100000)),
          wire.CurrencyBalance(currency: 'EUR', amountMinor: Int64(5000)),
        ],
      ),
    ),
  ).value;
  final category = Device.ok(
    await ledger.createCategory(
      wire.CreateCategoryRequest(
        title: 'Bills',
        iconKey: 'food',
        kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE,
      ),
    ),
  );
  return (account: account.id, category: category.id);
}

wire.Recurrence recurrence({
  wire.RecurrenceFrequency frequency = wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_ONCE,
  int? interval,
  String start = '2026-11-20',
  String zone = 'UTC',
  String? until,
  int? count,
}) {
  final out = wire.Recurrence(frequency: frequency, startDate: start, timeZone: zone);
  if (interval != null) out.interval = interval;
  if (until != null) out.untilDate = until;
  if (count != null) out.occurrenceCount = count;
  return out;
}

wire.CreatePlanRequest planRequest(
  ({String account, String category}) world, {
  String title = 'Rent',
  int amount = -150000,
  String currency = 'PLN',
  wire.Recurrence? recurrence_,
  wire.Reminder? reminder,
}) => wire.CreatePlanRequest(
  title: title,
  amountMinor: Int64(amount),
  currency: currency,
  accountId: world.account,
  categoryId: world.category,
  recurrence: recurrence_ ?? recurrence(),
  reminder: reminder,
);

wire.UpdatePlanRequest updateOf(wire.CreatePlanRequest r) => wire.UpdatePlanRequest(
  title: r.title,
  amountMinor: r.amountMinor,
  currency: r.currency,
  accountId: r.accountId,
  categoryId: r.categoryId,
  recurrence: r.recurrence,
  reminder: r.hasReminder() ? r.reminder : null,
);
