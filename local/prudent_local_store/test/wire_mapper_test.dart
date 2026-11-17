// The mapper between the store messages and the wire messages (phase-0 §0.3 row 4.1): every stored
// wire message round-trips, every difference between the two is an explicit input, and anything the
// other side cannot represent is refused rather than guessed at.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/budgets.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/records.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/settings.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';

const acc = '0123456789abcdef0123456789abcdef';
const acc2 = '11111111111111111111111111111111';
const cat = '22222222222222222222222222222222';
const rec = '33333333333333333333333333333333';
const tr = '44444444444444444444444444444444';
const goal = '55555555555555555555555555555555';
const goal2 = '66666666666666666666666666666666';
const plan = '77777777777777777777777777777777';
const dev = '88888888888888888888888888888888';

/// Equal as the store sees them: the same serialised bytes. A message built with an explicit default
/// (`note: ''`) and one with the field unset are one record to zen_store, which merges the bytes;
/// GeneratedMessage's `==` tells them apart, which is not a difference this mapper can make.
Matcher sameAs(GeneratedMessage expected) => predicate<GeneratedMessage>(
  (actual) =>
      actual.runtimeType == expected.runtimeType &&
      _bytes(actual).toString() == _bytes(expected).toString(),
  'the same bytes as $expected',
);

List<int> _bytes(GeneratedMessage m) => m.writeToBuffer();

void main() {
  group('enums are kept value for value', () {
    void same(
      List<ProtobufEnum> wireValues,
      List<ProtobufEnum> localValues,
      String wirePrefix,
      String localPrefix,
    ) {
      expect(localValues.map((v) => v.value), wireValues.map((v) => v.value));
      for (var i = 0; i < wireValues.length; i++) {
        expect(
          localValues[i].name.substring(localPrefix.length),
          wireValues[i].name.substring(wirePrefix.length),
        );
      }
    }

    test('every wire value has its local counterpart, by number and by name', () {
      same(wire.AccountType.values, AccountKind.values, 'ACCOUNT_TYPE_', 'ACCOUNT_KIND_');
      same(
        wire.CategoryKind.values,
        CategoryDirection.values,
        'CATEGORY_KIND_',
        'CATEGORY_DIRECTION_',
      );
      same(wire.GoalStatus.values, GoalState.values, 'GOAL_STATUS_', 'GOAL_STATE_');
      same(
        wire.GoalAllocationKind.values,
        AllocationKind.values,
        'GOAL_ALLOCATION_KIND_',
        'ALLOCATION_KIND_',
      );
      same(
        wire.RecurrenceFrequency.values,
        Frequency.values,
        'RECURRENCE_FREQUENCY_',
        'FREQUENCY_',
      );
    });
  });

  group('round trips', () {
    test('an account: openings and position here, derived balances and is_default on the wire', () {
      final account = Account(
        id: acc,
        name: 'Bank',
        kind: AccountKind.ACCOUNT_KIND_CHECKING,
        active: true,
        includeInTotal: true,
        includeInOverview: false,
        eligibleForGoals: true,
        accountNumber: 'PL00000000000000000000000003',
      );
      final currencies = [
        AccountCurrency(
          id: DerivedIds.accountCurrency(acc, 'EUR'),
          accountId: acc,
          currency: 'EUR',
          openingMinor: Int64(500),
          position: 1,
        ),
        AccountCurrency(
          id: DerivedIds.accountCurrency(acc, 'PLN'),
          accountId: acc,
          currency: 'PLN',
          openingMinor: Int64(10000),
        ),
      ];
      final out = WireMapper.accountToWire(
        account,
        currencies: currencies,
        settings: Settings(id: 'settings', mainCurrency: 'PLN', defaultAccountId: acc),
        balanceMinor: {'PLN': 8750, 'EUR': 500},
      );
      expect(out.isDefault, isTrue);
      expect(out.type, wire.AccountType.ACCOUNT_TYPE_CHECKING);
      // Ordered by position: the wire shows the current balance, never the opening.
      expect(out.balances.map((b) => (b.currency, b.amountMinor.toInt())), [
        ('PLN', 8750),
        ('EUR', 500),
      ]);

      final back = WireMapper.accountFromWire(out, openingMinor: {'PLN': 10000, 'EUR': 500});
      expect(back.account, sameAs(account));
      expect(back.isDefault, isTrue);
      expect(back.currencies, [currencies[1], currencies[0]]);
    });

    test('an account that is not the default, with no settings yet', () {
      final account = Account(id: acc, name: 'Cash');
      final out = WireMapper.accountToWire(
        account,
        currencies: const [],
        settings: null,
        balanceMinor: const {},
      );
      expect(out.isDefault, isFalse);
      expect(WireMapper.accountFromWire(out, openingMinor: const {}).account, sameAs(account));
    });

    test('a category', () {
      final category = Category(
        id: cat,
        title: 'Salary',
        iconKey: 'wallet',
        description: 'monthly',
        colorArgb: 0xFF00AA00,
        archived: true,
        kind: CategoryDirection.CATEGORY_DIRECTION_INCOME,
      );
      expect(WireMapper.categoryFromWire(WireMapper.categoryToWire(category)), sameAs(category));
    });

    test('an ordinary record, with every optional field and without', () {
      final full = Record(
        id: rec,
        title: 'Bread',
        posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(-1250)),
        date: '2026-11-02',
        categoryId: cat,
        payee: 'Bakery',
        note: 'rye',
      );
      final out = WireMapper.recordToWire(full);
      expect(out.hasTransferId(), isFalse);
      expect(out.isCorrection, isFalse);
      expect(WireMapper.recordFromWire(out), sameAs(full));
      final bare = Record(
        id: rec,
        title: '',
        posting: Posting(accountId: acc, currency: 'EUR', amountMinor: Int64(1)),
        date: '2026-01-01',
      );
      final bareOut = WireMapper.recordToWire(bare);
      expect([
        bareOut.hasCategoryId(),
        bareOut.hasPayee(),
        bareOut.hasNote(),
        bareOut.hasPlanId(),
      ], everyElement(isFalse));
      expect(WireMapper.recordFromWire(bareOut), sameAs(bare));
    });

    test('a correction keeps its intent locally; the wire says only is_correction', () {
      final correction = Record(
        id: rec,
        title: 'Balance correction',
        posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(300)),
        date: '2026-11-02',
        correction: CorrectionIntent(targetMinor: Int64(10300), seenMinor: Int64(10000)),
      );
      final out = WireMapper.recordToWire(correction);
      expect(out.isCorrection, isTrue);
      expect(WireMapper.recordFromWire(out, correction: correction.correction), sameAs(correction));
    });

    test('a confirming and an imported record keep their plan link and import key', () {
      final occurrence = DerivedIds.occurrence(plan, '2026-11-01');
      final confirming = Record(
        id: DerivedIds.confirmation(occurrence),
        title: 'Rent',
        posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(-90000)),
        date: '2026-11-01',
        categoryId: cat,
        planLink: PlanLink(planId: plan, occurrenceId: occurrence),
      );
      final out = WireMapper.recordToWire(confirming);
      expect((out.planId, out.planOccurrenceId), (plan, occurrence));
      expect(WireMapper.recordFromWire(out), sameAs(confirming));

      final key = ImportKey(fingerprint: 'v1:00ff', occurrence: 2);
      final imported = Record(
        id: DerivedIds.imported(acc, key.fingerprint, key.occurrence),
        title: 'Card',
        posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(-500)),
        date: '2026-11-04',
        categoryId: cat,
        importKey: key,
      );
      expect(
        WireMapper.recordFromWire(WireMapper.recordToWire(imported), importKey: key),
        sameAs(imported),
      );
    });

    test('a transfer is one store record and two wire legs with derived ids', () {
      final transfer = Transfer(
        id: tr,
        title: 'Exchange',
        date: '2026-11-03',
        source: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(4300)),
        destination: Posting(accountId: acc2, currency: 'EUR', amountMinor: Int64(1000)),
      );
      final out = WireMapper.transferToWire(transfer);
      expect(out.fromRecord.id, DerivedIds.transferLeg(tr, source: true));
      expect(out.toRecord.id, DerivedIds.transferLeg(tr, source: false));
      expect(out.fromRecord.amountMinor, Int64(-4300)); // the server's sign
      expect(out.toRecord.amountMinor, Int64(1000));
      expect([out.fromRecord.transferId, out.toRecord.transferId], [tr, tr]);
      expect(WireMapper.transferFromWire(out), sameAs(transfer));
    });

    test('a budget takes the id its slot derives', () {
      final budget = Budget(
        id: DerivedIds.budget(cat, '2026-11', 'PLN'),
        categoryId: cat,
        month: '2026-11',
        currency: 'PLN',
        amountMinor: Int64(50000),
      );
      expect(WireMapper.budgetFromWire(WireMapper.budgetToWire(budget)), sameAs(budget));
    });

    test('a carry-over reset, live and revoked', () {
      final live = BudgetCarryOverReset(
        id: rec,
        categoryId: cat,
        month: '2026-11',
        currency: 'PLN',
        discardedMinor: Int64(-300),
        note: 'restart',
        createdBy: dev,
        createdAtMs: Int64(17),
      );
      final liveOut = WireMapper.resetToWire(live);
      expect((liveOut.revokedBy, liveOut.revokedAtMs), ('', Int64.ZERO));
      expect(WireMapper.resetFromWire(liveOut), sameAs(live));
      final revoked = live.deepCopy()..revocation = Revocation(by: dev, atMs: Int64(99));
      final revokedOut = WireMapper.resetToWire(revoked);
      expect((revokedOut.revokedBy, revokedOut.revokedAtMs), (dev, Int64(99)));
      expect(WireMapper.resetFromWire(revokedOut), sameAs(revoked));
    });

    test('a goal, with and without a target date', () {
      final dated = Goal(
        id: goal,
        name: 'Bike',
        currency: 'PLN',
        targetAmountMinor: Int64(200000),
        targetDate: '2027-06-01',
        status: GoalState.GOAL_STATE_COMPLETED,
        statusChangedAtMs: Int64(5),
        createdAtMs: Int64(1),
      );
      expect(WireMapper.goalFromWire(WireMapper.goalToWire(dated)), sameAs(dated));
      final open = dated.deepCopy()..clearTargetDate();
      expect(WireMapper.goalToWire(open).hasTargetDate(), isFalse);
      expect(WireMapper.goalFromWire(WireMapper.goalToWire(open)), sameAs(open));
    });

    test('goal allocations of every kind', () {
      for (final entry in [
        GoalAllocation(
          id: rec,
          kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
          targetGoalId: goal,
          currency: 'PLN',
          amountMinor: Int64(100),
          note: 'n',
          createdAtMs: Int64(1),
          createdBy: dev,
        ),
        GoalAllocation(
          id: rec,
          kind: AllocationKind.ALLOCATION_KIND_WITHDRAW,
          sourceGoalId: goal,
          currency: 'PLN',
          amountMinor: Int64(50),
          createdAtMs: Int64(2),
          createdBy: dev,
        ),
        GoalAllocation(
          id: rec,
          kind: AllocationKind.ALLOCATION_KIND_MOVE,
          sourceGoalId: goal,
          targetGoalId: goal2,
          currency: 'PLN',
          amountMinor: Int64(25),
          createdAtMs: Int64(3),
          createdBy: dev,
        ),
      ]) {
        expect(WireMapper.allocationFromWire(WireMapper.allocationToWire(entry)), sameAs(entry));
      }
    });

    test('a repair entry: its compensated entries are local-only, an input going in', () {
      final repair = GoalAllocation(
        id: rec,
        kind: AllocationKind.ALLOCATION_KIND_ALLOCATE,
        targetGoalId: goal,
        currency: 'PLN',
        amountMinor: Int64(500),
        createdAtMs: Int64(4),
        compensates: [goal, goal2],
      );
      final out = WireMapper.allocationToWire(repair);
      expect(out.writeToJson().contains(goal2), isFalse);
      expect(WireMapper.allocationFromWire(out, compensates: repair.compensates), sameAs(repair));
    });

    test('a plan with each kind of schedule end and reminder', () {
      final base = Plan(
        id: plan,
        title: 'Rent',
        posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(-90000)),
        categoryId: cat,
        payee: 'Landlord',
        note: 'flat',
        schedule: Schedule(
          frequency: Frequency.FREQUENCY_MONTHLY,
          interval: 1,
          startDate: '2026-11-01',
          timeZone: 'Europe/Warsaw',
        ),
        reminder: ReminderSetting(enabled: true, leadDays: 3),
      );
      for (final variant in [
        base,
        base.deepCopy()..schedule = (base.schedule.deepCopy()..untilDate = '2027-12-01'),
        base.deepCopy()..schedule = (base.schedule.deepCopy()..occurrenceCount = 12),
        base.deepCopy()..reminder = ReminderSetting(enabled: false),
        base.deepCopy()
          ..clearReminder()
          ..clearPayee()
          ..clearNote(),
      ]) {
        expect(WireMapper.planFromWire(WireMapper.planToWire(variant)), sameAs(variant));
      }
    });

    test(
      'an occurrence: status and copied fields are derived inputs; skip and read time are stored',
      () {
        final p = Plan(
          id: plan,
          title: 'Rent',
          posting: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(-90000)),
          categoryId: cat,
        );
        final state = OccurrenceState(
          id: DerivedIds.occurrence(plan, '2026-12-01'),
          planId: plan,
          occurrenceDate: '2026-12-01',
          skipped: true,
          reminderReadAtMs: Int64(44),
        );
        final out = WireMapper.occurrenceToWire(
          plan: p,
          date: '2026-12-01',
          status: wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED,
          state: state,
        );
        expect(
          (out.title, out.amountMinor.toInt(), out.accountId, out.categoryId),
          ('Rent', -90000, acc, cat),
        );
        expect(WireMapper.occurrenceFromWire(out, reminderReadAtMs: 44), sameAs(state));
      },
    );

    test('settings: the default account is a setting here and an account flag on the wire', () {
      final s = Settings(id: 'settings', mainCurrency: 'PLN', defaultAccountId: acc);
      final out = WireMapper.settingsToWire(s);
      expect(out, wire.Settings(mainCurrency: 'PLN'));
      expect(WireMapper.settingsFromWire(out, defaultAccountId: acc), sameAs(s));
      expect(WireMapper.settingsFromWire(out).hasDefaultAccountId(), isFalse);
    });
  });

  group('refusals', () {
    test('a transfer leg is not a record', () {
      expect(
        () => WireMapper.recordFromWire(wire.Record(id: rec, transferId: tr)),
        throwsArgumentError,
      );
    });

    test('a correction without its intent, and an intent on an ordinary record', () {
      expect(
        () => WireMapper.recordFromWire(wire.Record(id: rec, isCorrection: true)),
        throwsArgumentError,
      );
      expect(
        () => WireMapper.recordFromWire(wire.Record(id: rec), correction: CorrectionIntent()),
        throwsArgumentError,
      );
    });

    test('a plan id without its occurrence', () {
      expect(
        () => WireMapper.recordFromWire(wire.Record(id: rec, planId: plan)),
        throwsArgumentError,
      );
    });

    test('legs that do not form one transfer', () {
      final good = WireMapper.transferToWire(
        Transfer(
          id: tr,
          title: 'T',
          date: '2026-11-03',
          source: Posting(accountId: acc, currency: 'PLN', amountMinor: Int64(1)),
          destination: Posting(accountId: acc2, currency: 'PLN', amountMinor: Int64(1)),
        ),
      );
      for (final broken in <void Function(wire.Transfer)>[
        (t) => t.toRecord.transferId = rec,
        (t) => t.toRecord.date = '2026-11-04',
        (t) => t.toRecord.title = 'other',
        (t) => t.fromRecord.amountMinor = Int64(1),
        (t) => t.toRecord.amountMinor = Int64(-1),
        (t) => t.toRecord.categoryId = cat,
        (t) => t.fromRecord.isCorrection = true,
      ]) {
        final t = good.deepCopy();
        broken(t);
        expect(() => WireMapper.transferFromWire(t), throwsArgumentError);
      }
    });

    test('balances or openings that do not name exactly the held currencies', () {
      final c = AccountCurrency(
        id: DerivedIds.accountCurrency(acc, 'PLN'),
        accountId: acc,
        currency: 'PLN',
      );
      expect(
        () => WireMapper.accountToWire(
          Account(id: acc),
          currencies: [c],
          settings: null,
          balanceMinor: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => WireMapper.accountToWire(
          Account(id: acc2),
          currencies: [c],
          settings: null,
          balanceMinor: const {'PLN': 1},
        ),
        throwsArgumentError,
      );
      final out = wire.Account(
        id: acc,
        balances: [wire.CurrencyBalance(currency: 'PLN')],
      );
      expect(
        () => WireMapper.accountFromWire(out, openingMinor: const {'EUR': 1}),
        throwsArgumentError,
      );
      final twice = wire.Account(
        id: acc,
        balances: [
          wire.CurrencyBalance(currency: 'PLN'),
          wire.CurrencyBalance(currency: 'PLN'),
        ],
      );
      expect(
        () => WireMapper.accountFromWire(twice, openingMinor: const {'PLN': 1}),
        throwsArgumentError,
      );
    });

    test('a half-revoked reset', () {
      expect(
        () => WireMapper.resetFromWire(wire.BudgetCarryOverReset(id: rec, revokedBy: dev)),
        throwsArgumentError,
      );
    });

    test('an occurrence state of another plan or date', () {
      final p = Plan(id: plan, posting: Posting());
      final state = OccurrenceState(
        id: DerivedIds.occurrence(plan, '2026-12-02'),
        planId: plan,
        occurrenceDate: '2026-12-02',
      );
      expect(
        () => WireMapper.occurrenceToWire(
          plan: p,
          date: '2026-12-01',
          status: wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED,
          state: state,
        ),
        throwsArgumentError,
      );
    });
  });
}
