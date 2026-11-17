// Unit 10b (ADR-103, ADR-123): the server's privacy export moved into an empty Local store, once,
// all or nothing, refused whole unless every balance matches to the cent.
//
// These tests break a synthetic export on purpose. The export the real server makes is moved in by
// tools/prudent_parity_server/test/move_in_test.dart, which compares every figure with the server's.
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/goals.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/goal_allocations.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/plans.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart' as wire;
import 'package:protobuf/protobuf.dart';
import 'package:test/test.dart';
import 'package:zen_store/zen_store.dart';

import 'support/export_builder.dart';
import 'support/imports.dart';
import 'support/two_devices.dart' show TwoDevices;

const _completed = wire.OccurrenceStatus.OCCURRENCE_STATUS_COMPLETED;
const _skipped = wire.OccurrenceStatus.OCCURRENCE_STATUS_SKIPPED;
const _planned = wire.OccurrenceStatus.OCCURRENCE_STATUS_PLANNED;

/// A whole ledger: two accounts in three currencies, records under categories, a cross-currency
/// transfer, two corrections, a plan with a completed, a skipped and a planned occurrence, budgets
/// and resets, goals with every kind of allocation, and an open import session.
({ExportBuilder b, String wallet, String bank, String food, String plan}) _ledger() {
  final b = ExportBuilder();
  final wallet = b.account('Wallet', {'PLN': 10000, 'EUR': 500}, isDefault: true);
  final bank = b.account('Bank', {'PLN': 250000}, eligibleForGoals: true);
  final food = b.category('Food', kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE);
  final salary = b.category('Salary', kind: wire.CategoryKind.CATEGORY_KIND_INCOME);
  final old = b.category('Old', archived: true);
  b.record(wallet, 'PLN', -1250, category: food, date: '2026-09-02');
  b.record(wallet, 'EUR', -120, category: old, date: '2026-09-03');
  b.record(bank, 'PLN', 500000, category: salary, date: '2026-09-28', title: 'Pay');
  b.record(bank, 'PLN', -3999, category: food, date: '2026-10-02');
  b.transfer(bank, 'PLN', wallet, 'EUR', 43000, received: 10000, date: '2026-10-03');
  b.correction(wallet, 'PLN', 300, date: '2026-10-10');
  b.correction(wallet, 'PLN', -50, date: '2026-10-20');
  final plan = b.plan(bank, 'PLN', -180000, food, '2026-09-01');
  b.confirmation(b.occurrence(plan, '2026-09-01', _completed));
  b.occurrence(plan, '2026-10-01', _skipped);
  b.occurrence(plan, '2026-11-01', _planned);
  b.budget(food, '2026-09', 'PLN', 50000);
  b.budget(food, '2026-10', 'PLN', 40000);
  b.reset(food, '2026-10', 'PLN', revoked: true);
  b.reset(food, '2026-11', 'PLN');
  final trip = b.goal('Trip', 'PLN', 300000, targetDate: '2027-06-30');
  final bike = b.goal('Bike', 'PLN', 90000);
  b.allocation(wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_ALLOCATE, 'PLN', 60000, target: trip);
  b.allocation(
    wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_WITHDRAW,
    'PLN',
    5000,
    source: trip,
    atMs: 1790000200000,
  );
  b.allocation(
    wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_MOVE,
    'PLN',
    10000,
    source: trip,
    target: bike,
    atMs: 1790000300000,
  );
  b.openImportSession();
  return (b: b, wallet: wallet, bank: bank, food: food, plan: plan);
}

void main() {
  late ImportWorld w;

  setUp(() async => w = await ImportWorld.create());
  tearDown(() async => w.dispose());

  MoveInRefusal refusedWith(MoveInResult result, MoveInRule rule) => switch (result) {
    MovedIn() => fail('expected ${rule.code}, the move was written'),
    MoveInRefused(:final refusal) =>
      refusal.rule == rule ? refusal : fail('expected ${rule.code}, got $refusal'),
  };

  MoveInSummary moved(MoveInResult result) => switch (result) {
    MovedIn(:final summary) => summary,
    MoveInRefused(:final refusal) => fail('expected the move to be written, got $refusal'),
  };

  group('a whole ledger', () {
    test('moves in, and every balance is the exported one to the cent', () async {
      final l = _ledger();
      final export = l.b.build();
      final summary = moved(await MoveIn(w.store).run(export));

      expect(summary.accounts, 2);
      expect(summary.categories, 3);
      expect(summary.transfers, 1);
      // Four ordinary, two corrections, one confirmation; the transfer's legs are one record above.
      expect(summary.records, 7);
      expect(summary.plans, 1);
      expect(summary.skippedOccurrences, 1);
      expect(summary.budgets, 2);
      expect(summary.carryOverResets, 2);
      expect(summary.goals, 2);
      expect(summary.goalAllocations, 3);
      expect(summary.droppedImportSessions, 1);

      final accounts = ok(await w.ledger.listAccounts());
      expect(accounts.isSettled, isTrue);
      final local = {
        for (final a in accounts.value.accounts)
          a.id: {for (final b in a.balances) b.currency: b.amountMinor},
      };
      for (final account in export.accounts) {
        expect(local[ExportBuilder.local(account.id)], {
          for (final b in account.balances) b.currency: b.amountMinor,
        });
      }
      // The default account moved into settings, and the opening was rebuilt (F-03).
      final wallet = ok(await w.ledger.getAccount(ExportBuilder.local(l.wallet))).value;
      expect(wallet.isDefault, isTrue);
      final opening = ok(
        w.store.accountCurrencies.get(
          DerivedIds.accountCurrency(ExportBuilder.local(l.wallet), 'PLN'),
        ),
      );
      expect(opening.openingMinor, Int64(10000));
    });

    test('keeps the server ids, joins the transfer, and remaps the confirmation', () async {
      final l = _ledger();
      final export = l.b.build();
      moved(await MoveIn(w.store).run(export));

      final transfers = ok(w.store.transfers.list());
      expect(transfers, hasLength(1));
      final transfer = transfers.single;
      expect(transfer.source.amountMinor, Int64(43000));
      expect(transfer.destination.amountMinor, Int64(10000));
      expect(transfer.destination.currency, 'EUR');

      final plan = ExportBuilder.local(l.plan);
      final occurrence = DerivedIds.occurrence(plan, '2026-09-01');
      final confirmation = ok(w.store.records.get(DerivedIds.confirmation(occurrence)));
      expect(confirmation.planLink.occurrenceDate, '2026-09-01');
      expect(confirmation.planLink.planId, plan);

      final skipped = ok(w.store.occurrences.get(DerivedIds.occurrence(plan, '2026-10-01')));
      expect(skipped.skipped, isTrue);
      // A planned occurrence is read from the schedule, never stored (ADR-119).
      expect(ok(w.store.occurrences.list()), hasLength(1));

      // Every other row keeps its server id in Local form.
      final categoryIds = {for (final c in ok(w.store.categories.list())) c.id};
      expect(categoryIds, {for (final c in export.categories) ExportBuilder.local(c.id)});
    });

    test('corrections see each other, so no integrity issue appears', () async {
      moved(await MoveIn(w.store).run(_ledger().b.build()));
      final corrections = [
        for (final r in ok(w.store.records.list()))
          if (r.hasCorrection()) r,
      ]..sort((a, b) => a.date.compareTo(b.date));
      expect(corrections, hasLength(2));
      expect(corrections.first.correction.seenCorrections, isEmpty);
      expect(corrections.last.correction.seenCorrections, [corrections.first.id]);
      // Seen 10000 − 1250 opening-and-bread, asked 10000 − 1250 + 300.
      expect(corrections.first.correction.seenMinor, Int64(8750));
      expect(corrections.first.correction.targetMinor, Int64(9050));
      expect(ok(IntegrityRunner(w.store).evaluate()), isEmpty);
    });

    test('the export read back from its JSON file moves in the same', () async {
      final export = _ledger().b.build();
      final file = utf8.encode(const JsonEncoder.withIndent('  ').convert(export.toProto3Json()));
      final read = MoveIn.read(file);
      expect(read, export);
      moved(await MoveIn(w.store).run(read));
    });
  });

  group('statement keys', () {
    test('a statement imported on the server is a duplicate when imported again after the move', () async {
      // The source of the keys: a statement committed into an account, as the server's commit does,
      // whose fingerprints embed the account id in the server's form (ADR-091, ADR-112).
      final source = await ImportWorld.create();
      addTearDown(source.dispose);
      final account = await source.account();
      final spending = await source.category(
        'Spending',
        kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE,
      );
      final income = await source.category('Income', kind: wire.CategoryKind.CATEGORY_KIND_INCOME);
      final session = await source.previewed(
        Erste.base(),
        account: account,
        expense: spending,
        income: income,
      );
      ok(await source.commit(session.id, 5));

      final b = ExportBuilder();
      final serverAccount = b.account(
        'Erste',
        {'PLN': 0},
        accountNumber: Erste.account,
        id: ExportBuilder.serverForm(account),
      );
      final category = b.category('Spending', kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE);
      final incomeCategory = b.category('Income', kind: wire.CategoryKind.CATEGORY_KIND_INCOME);
      for (final r in source.records().values) {
        b.imported(
          serverAccount,
          'PLN',
          r.posting.amountMinor.toInt(),
          category: r.posting.amountMinor > 0 ? incomeCategory : category,
          fingerprint: r.importKey.fingerprint,
          occurrence: r.importKey.occurrence,
          date: r.date,
        );
      }
      final summary = moved(await MoveIn(w.store).run(b.build()));
      expect(summary.importKeys, 5);
      for (final r in ok(w.store.records.list())) {
        expect(r.id, DerivedIds.imported(account, r.importKey.fingerprint, r.importKey.occurrence));
      }

      final again = await w.previewed(
        Erste.base(),
        account: account,
        expense: ExportBuilder.local(category),
        income: ExportBuilder.local(incomeCategory),
      );
      expect(again.duplicateRows, 5);
      expect(again.acceptedRows, 0);
    });

    test('a key of an unknown version is refused, not guessed at', () async {
      final b = ExportBuilder();
      final a = b.account('Erste', {'PLN': 0});
      final c = b.category('Spending');
      b.imported(a, 'PLN', -100, category: c, fingerprint: 'v2:${'0' * 64}', occurrence: 1);
      refusedWith(await MoveIn(w.store).run(b.build()), MoveInRule.importKey);
      expect(ok(w.store.records.list()), isEmpty);
    });

    test('a key on a transfer leg is refused', () async {
      final b = ExportBuilder();
      final a = b.account('A', {'PLN': 0});
      final c = b.account('C', {'PLN': 0});
      b.transfer(a, 'PLN', c, 'PLN', 100);
      final export = b.build();
      export.recordImportKeys.add(
        wire.ExportImportKey(
          recordId: export.records.first.id,
          fingerprint: 'v1:${'a' * 64}',
          occurrence: 1,
        ),
      );
      refusedWith(await MoveIn(w.store).run(export), MoveInRule.importKey);
    });
  });

  group('refused whole, nothing written', () {
    Future<void> expectNothingWritten(wire.DataExport export, MoveInRule rule) async {
      final before = w.snapshot();
      refusedWith(await MoveIn(w.store).run(export), rule);
      expect(w.snapshot(), before);
    }

    test('a store that already holds data', () async {
      await w.category('Mine');
      await expectNothingWritten(_ledger().b.build(), MoveInRule.storeNotEmpty);
    });

    test('a second move of the same export into the store it filled', () async {
      final export = _ledger().b.build();
      moved(await MoveIn(w.store).run(export));
      await expectNothingWritten(export, MoveInRule.storeNotEmpty);
    });

    test('an unknown format version', () async {
      await expectNothingWritten(_ledger().b.build()..formatVersion = 2, MoveInRule.formatVersion);
    });

    test('a transfer with one leg missing', () async {
      final export = _ledger().b.build();
      export.records.removeWhere((r) => r.hasTransferId() && r.amountMinor > 0);
      // Refused at the join, before any balance is compared.
      await expectNothingWritten(export, MoveInRule.transferBroken);
    });

    test('a record on an account the export does not hold', () async {
      final export = _ledger().b.build();
      export.records.first.accountId = '00000000-0000-4000-8000-999999999999';
      await expectNothingWritten(export, MoveInRule.unknownReference);
    });

    test('a record in a currency its account does not hold', () async {
      final export = _ledger().b.build();
      export.records.first.currency = 'CHF';
      await expectNothingWritten(export, MoveInRule.currencyNotHeld);
    });

    test('an id the server does not write', () async {
      final export = _ledger().b.build();
      export.categories.first.id = 'not-an-id';
      await expectNothingWritten(export, MoveInRule.malformedId);
    });

    test('two accounts marked default', () async {
      final export = _ledger().b.build();
      for (final a in export.accounts) {
        a.isDefault = true;
      }
      await expectNothingWritten(export, MoveInRule.twoDefaults);
    });

    test('a completed occurrence no record confirms', () async {
      final export = _ledger().b.build();
      export.records.removeWhere((r) => r.hasPlanOccurrenceId());
      await expectNothingWritten(export, MoveInRule.occurrenceUnpaired);
    });

    test('a plan in a zone Local cannot read the calendar of', () async {
      final export = _ledger().b.build();
      export.plans.first.recurrence.timeZone = 'Africa/Casablanca';
      await expectNothingWritten(export, MoveInRule.planZone);
    });

    group('a value the server would not have stored', () {
      // One per class of value (review S2 on #273): each is refused whole as `invalid_value`, naming
      // the collection and field, before anything is written.
      final cases = <String, (String, String, void Function(wire.DataExport))>{
        'a record date that is not a date': (
          'records',
          'date',
          (e) => e.records.first.date = '2026-13-45',
        ),
        'a record date that is not canonical': (
          'records',
          'date',
          (e) => e.records.first.date = '2026-9-02',
        ),
        'a record currency in lower case': (
          'records',
          'currency',
          (e) => e.records.first.currency = 'pln',
        ),
        'a record of zero': ('records', 'amount', (e) => e.records.first.amountMinor = Int64.ZERO),
        'an account with no type': (
          'accounts',
          'type',
          (e) => e.accounts.first.type = wire.AccountType.ACCOUNT_TYPE_UNSPECIFIED,
        ),
        'an account currency that is not one': (
          'accounts',
          'currency',
          (e) => e.accounts.first.balances.first.currency = 'XX',
        ),
        'a goal currency that is not one': (
          'goals',
          'currency',
          (e) => e.goals.first.currency = 'xx',
        ),
        'a goal target of zero': (
          'goals',
          'target',
          (e) => e.goals.first.targetAmountMinor = Int64.ZERO,
        ),
        'a goal with no status': (
          'goals',
          'status',
          (e) => e.goals.first.status = wire.GoalStatus.GOAL_STATUS_UNSPECIFIED,
        ),
        'a goal target date that is not a date': (
          'goals',
          'target_date',
          (e) => e.goals.first.targetDate = '2027-02-30',
        ),
        'an envelope entry with no kind': (
          'goal_allocations',
          'kind',
          (e) => e.goalAllocations.first.kind =
              wire.GoalAllocationKind.GOAL_ALLOCATION_KIND_UNSPECIFIED,
        ),
        'an allocation with no goal to go into': (
          'goal_allocations',
          'target_goal',
          (e) => e.goalAllocations.first.clearTargetGoalId(),
        ),
        'an envelope entry of zero': (
          'goal_allocations',
          'amount',
          (e) => e.goalAllocations.first.amountMinor = Int64.ZERO,
        ),
        'a move into the goal it comes from': (
          'goal_allocations',
          'target_goal',
          (e) => e.goalAllocations.last.targetGoalId = e.goalAllocations.last.sourceGoalId,
        ),
        'an envelope entry in another currency than its goal': (
          'goal_allocations',
          'currency',
          (e) => e.goalAllocations.first.currency = 'EUR',
        ),
        'a budget month that is not one': (
          'budgets',
          'month',
          (e) => e.budgets.first.month = '2026-13',
        ),
        'a budget of zero': ('budgets', 'amount', (e) => e.budgets.first.amountMinor = Int64.ZERO),
        'a reset month that is not one': (
          'carry_over_resets',
          'month',
          (e) => e.carryOverResets.first.month = '2026-1',
        ),
        'a plan of zero': ('plans', 'amount', (e) => e.plans.first.amountMinor = Int64.ZERO),
        'a plan whose recurrence has no frequency': (
          'plans',
          'recurrence',
          (e) => e.plans.first.recurrence.frequency =
              wire.RecurrenceFrequency.RECURRENCE_FREQUENCY_UNSPECIFIED,
        ),
        'a plan with no recurrence': (
          'plans',
          'recurrence',
          (e) => e.plans.first.clearRecurrence(),
        ),
        'a reminder lead time the rules refuse': (
          'plans',
          'reminder',
          (e) => e.plans.first.reminder = wire.Reminder(enabled: true, leadDays: 5),
        ),
        'an occurrence date that is not a date': (
          'occurrences',
          'date',
          (e) => e.occurrences.last.occurrenceDate = '2026-11-31',
        ),
        'a main currency in lower case': (
          'settings',
          'main_currency',
          (e) => e.settings.mainCurrency = 'pln',
        ),
      };
      for (final MapEntry(key: name, value: (collection, field, breakIt)) in cases.entries) {
        test(name, () async {
          final export = _ledger().b.build();
          breakIt(export);
          final before = w.snapshot();
          final refusal = refusedWith(await MoveIn(w.store).run(export), MoveInRule.invalidValue);
          expect(refusal.facts['collection'], collection, reason: '$refusal');
          expect(refusal.facts['field'], field, reason: '$refusal');
          expect(w.snapshot(), before);
        });
      }

      test('a transfer whose two legs are on one account', () async {
        final export = _ledger().b.build();
        final legs = export.records.where((r) => r.hasTransferId()).toList();
        final source = legs.singleWhere((r) => r.amountMinor < 0);
        legs.singleWhere((r) => r.amountMinor > 0)
          ..accountId = source.accountId
          ..currency = source.currency;
        await expectNothingWritten(export, MoveInRule.transferBroken);
      });

      test(
        'no settings is the server\'s export of a person who never saved any, and moves in',
        () async {
          final export = _ledger().b.build()..clearSettings();
          moved(await MoveIn(w.store).run(export));
        },
      );

      test(
        'a same-currency transfer with a fee between its legs is the server\'s, and moves in',
        () async {
          // `TransferResource.create` takes the two amounts apart and never requires them equal.
          final b = ExportBuilder();
          final one = b.account('One', {'PLN': 10000}, isDefault: true);
          final two = b.account('Two', {'PLN': 0});
          b.transfer(one, 'PLN', two, 'PLN', 5000, received: 4900);
          moved(await MoveIn(w.store).run(b.build()));
        },
      );
    });

    test('a record dropped on the way in fails the balance check (ADR-103)', () async {
      final before = w.snapshot();
      final result = await MoveIn(
        w.store,
        fault: (records, transfers) => records.remove(records.keys.first),
      ).run(_ledger().b.build());
      final refusal = refusedWith(result, MoveInRule.balanceMismatch);
      expect(refusal.facts.keys, containsAll(['account', 'currency', 'expected', 'actual']));
      expect(w.snapshot(), before);
    });

    test('a transfer mis-joined on the way in fails the balance check', () async {
      final result = await MoveIn(
        w.store,
        fault: (records, transfers) {
          final t = transfers.values.single;
          t.destination = t.destination.deepCopy()..amountMinor = t.source.amountMinor;
        },
      ).run(_ledger().b.build());
      refusedWith(result, MoveInRule.balanceMismatch);
    });

    test('data a sync delivers between the check and the write', () async {
      // The emptiness check passes, then a category another device made lands before the batch takes
      // its turn: the batch's first precondition finds the store no longer empty, and nothing of the
      // move is written.
      final devices = await TwoDevices.create();
      addTearDown(devices.dispose);
      final elsewhere = await Ledger(devices.phone.store)
          .createCategory(wire.CreateCategoryRequest(title: 'Elsewhere', iconKey: 'food'));
      final name = 'categories:${ok(elsewhere).id}';
      final arriving = devices.laptop.zen.receive([
        ZenIncomingRecord(name, devices.phone.zen.outgoing(name)!.payload, null),
      ]);
      final result = await MoveIn(devices.laptop.store).run(_ledger().b.build());
      expect((await arriving).isSuccess, isTrue);
      // Refused by the write's own precondition (it carries the store's error), not by the check
      // before it, which ran while the store was still empty.
      expect(refusedWith(result, MoveInRule.storeNotEmpty).cause, isNotNull);
      final store = devices.laptop.store;
      expect(ok(store.records.list()), isEmpty);
      expect(ok(store.accounts.list()), isEmpty);
      expect(ok(store.categories.list()).single.title, 'Elsewhere');
    });
  });

  group('the file', () {
    test('that is not JSON, or not an export, or holds a field this build does not know', () {
      for (final text in ['not json', '[1, 2]', '{"formatVersion": 1, "surprise": true}']) {
        expect(
          () => MoveIn.read(utf8.encode(text)),
          throwsA(isA<MoveInRefusal>().having((r) => r.rule, 'rule', MoveInRule.unreadable)),
          reason: text,
        );
      }
    });

    test('with a 64-bit integer outside its range, which the reader would wrap', () {
      final json = _ledger().b.build().toProto3Json()! as Map<String, Object?>;
      final records = json['records']! as List<Object?>;
      for (final (value, path) in [
        ('9223372036854775808', 'one above the largest'),
        ('-9223372036854775809', 'one below the smallest'),
        ('99999999999999999999', 'far above'),
        ('12.5', 'not whole'),
      ]) {
        final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        ((copy['records']! as List<Object?>).first! as Map<String, Object?>)['amountMinor'] = value;
        expect(
          () => MoveIn.read(utf8.encode(jsonEncode(copy))),
          throwsA(isA<MoveInRefusal>().having((r) => r.rule, 'rule', MoveInRule.unreadable)),
          reason: path,
        );
      }
      // Nested, and by its proto name: a goal's target and an account balance.
      for (final edit in <void Function(Map<String, Object?>)>[
        (j) =>
            ((j['goals']! as List<Object?>).first! as Map<String, Object?>)['target_amount_minor'] =
                '9223372036854775808',
        (j) =>
            ((((j['accounts']! as List<Object?>).first! as Map<String, Object?>)['balances']!
                            as List<Object?>)
                        .first!
                    as Map<String, Object?>)['amountMinor'] =
                '-9223372036854775809',
      ]) {
        final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
        edit(copy);
        expect(
          () => MoveIn.read(utf8.encode(jsonEncode(copy))),
          throwsA(isA<MoveInRefusal>().having((r) => r.rule, 'rule', MoveInRule.unreadable)),
        );
      }
      // The extremes themselves read, as strings and as numbers.
      final edge = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      ((edge['records']! as List<Object?>)[0]! as Map<String, Object?>)['amountMinor'] =
          '9223372036854775807';
      ((edge['records']! as List<Object?>)[1]! as Map<String, Object?>)['amountMinor'] = -42;
      final read = MoveIn.read(utf8.encode(jsonEncode(edge)));
      expect(read.records[0].amountMinor, Int64.MAX_VALUE);
      expect(read.records[1].amountMinor, Int64(-42));
      expect(records, isNotEmpty);
    });

    test('never quotes a title, payee or note in a refusal', () async {
      final export = _ledger().b.build();
      export.records.first
        ..accountId = '00000000-0000-4000-8000-999999999999'
        ..title = 'SECRET TITLE'
        ..payee = 'SECRET PAYEE';
      final refusal = refusedWith(await MoveIn(w.store).run(export), MoveInRule.unknownReference);
      expect('$refusal', isNot(contains('SECRET')));
    });
  });

  group('two devices', () {
    /// Every synced collection of [store] beside the records [plan] says the move writes there.
    List<(ZenCollection<GeneratedMessage>, List<GeneratedMessage>)> pairs(
      PrudentLocalStore store,
      MoveInPlan plan,
    ) => [
      (store.accounts, plan.accounts),
      (store.accountCurrencies, plan.accountCurrencies),
      (store.categories, plan.categories),
      (store.records, plan.records),
      (store.transfers, plan.transfers),
      (store.plans, plan.plans),
      (store.occurrences, plan.occurrences),
      (store.budgets, plan.budgets),
      (store.budgetResets, plan.resets),
      (store.goals, plan.goals),
      (store.goalAllocations, plan.allocations),
      (store.settings, [plan.settings]),
    ];

    String idOf(GeneratedMessage m) => m.getField(1) as String;

    /// Every record of every synced collection, as bytes, by collection and id.
    Map<String, Map<String, String>> dump(PrudentLocalStore store, MoveInPlan plan) => {
      for (final (collection, _) in pairs(store, plan))
        collection.name: {
          for (final m in ok(collection.list())) idOf(m): base64.encode(m.writeToBuffer()),
        },
    };

    test('two moves of one export write the same records, byte for byte', () async {
      final devices = await TwoDevices.create();
      addTearDown(devices.dispose);
      final export = _ledger().b.build();
      final plan = MoveInPlan.of(export);
      for (final device in devices.both) {
        moved(await MoveIn(device.store).run(export));
      }
      final phone = dump(devices.phone.store, plan);
      expect(phone.values.every((records) => records.isNotEmpty), isTrue, reason: '$phone');
      expect(dump(devices.laptop.store, plan), phone);
    });

    test('the same export moved in on both is one copy after they sync', () async {
      final devices = await TwoDevices.create();
      addTearDown(devices.dispose);
      final export = _ledger().b.build();
      for (final device in devices.both) {
        moved(await MoveIn(device.store).run(export));
      }
      await devices.sync();
      // Every collection holds exactly the ids the export derives — a random id anywhere would
      // leave two copies after the sync, and a count or id set here would differ.
      final plan = MoveInPlan.of(export);
      for (final device in devices.both) {
        for (final (collection, planned) in pairs(device.store, plan)) {
          expect(
            ok(collection.list()).map(idOf).toSet(),
            planned.map(idOf).toSet(),
            reason: collection.name,
          );
          expect(ok(collection.list()), hasLength(planned.length), reason: collection.name);
          expect(ok(collection.conflicts()), isEmpty, reason: collection.name);
        }
      }
      expect(dump(devices.laptop.store, plan), dump(devices.phone.store, plan));
      expect(plan.resets, hasLength(2));
      expect(plan.goals, hasLength(2));
    });
  });
}
