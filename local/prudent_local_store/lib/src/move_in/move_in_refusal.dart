import 'package:meta/meta.dart';
import 'package:zen_core/zen_core.dart';

/// Why a move into Prudent Local was refused (unit 10b, ADR-103, ADR-123). A move is refused
/// whole: nothing of the export is written when any of these is found.
///
/// Each value names one reason the Local app explains in a sentence of its own, in en, uk and pl.
/// The [MoveInRefusal.facts] beside it are ids, field and currency codes, counts and amounts in
/// minor units — no free text: never a title, payee, note, account number or fingerprint. They are
/// for the person whose file it is, on the page; a log line names the error's class only.
enum MoveInRule {
  /// The file is not a `DataExport` in proto3 JSON, holds a field this app does not know, or a
  /// 64-bit integer outside its range. Either would be read silently wrong (a field dropped, a
  /// number wrapped), so it is refused instead.
  unreadable('move_in.unreadable'),

  /// `format_version` is not one this app reads (facts: `version`).
  formatVersion('move_in.format_version'),

  /// The store already holds data: a move goes into an empty store only, because two histories
  /// merged have no identity story (ADR-103).
  storeNotEmpty('move_in.store_not_empty'),

  /// An id is not one the server writes (facts: `collection`).
  malformedId('move_in.malformed_id'),

  /// Two rows of one collection carry one id, or two imported records one statement key
  /// (facts: `collection`, `id`).
  duplicateId('move_in.duplicate_id'),

  /// A row names an account, category, plan, occurrence, goal or record the export does not hold
  /// (facts: `collection`, `id`, `missing`, `missingId`).
  unknownReference('move_in.unknown_reference'),

  /// A record, transfer or plan uses a currency its account does not hold
  /// (facts: `collection`, `id`, `account`, `currency`).
  currencyNotHeld('move_in.currency_not_held'),

  /// A transfer has not exactly one source and one destination leg, its legs are on one account,
  /// or they disagree (facts: `transfer`, `legs`).
  transferBroken('move_in.transfer_broken'),

  /// More than one account is the default (facts: `count`).
  twoDefaults('move_in.two_defaults'),

  /// An occurrence's state disagrees with the records: completed with no record that confirms it,
  /// or a record confirms one that is skipped or planned (facts: `occurrence`).
  occurrenceUnpaired('move_in.occurrence_unpaired'),

  /// A plan's time zone is one Prudent Local cannot read the calendar of (`PlanZones.unsupported`;
  /// facts: `plan`).
  planZone('move_in.plan_zone'),

  /// A statement key is of a version this app does not know, or belongs to a record that a
  /// statement import cannot have written (a transfer leg, a correction, a confirmation)
  /// (facts: `record`).
  importKey('move_in.import_key'),

  /// A value the server would not have stored: a currency, month or date that is not canonical, a
  /// zero amount, an unknown type, kind or status, a goal target or budget that is not positive, an
  /// envelope entry without the goals its kind takes, a recurrence or reminder the plan rules refuse
  /// (facts: `collection`, `id`, `field`).
  invalidValue('move_in.invalid_value'),

  /// After the import an account's balance would not be the exported one, to the cent
  /// (facts: `account`, `currency`, `expected`, `actual`). This is the check ADR-103 names: it
  /// catches a dropped or mis-joined record. It does not check budgets, envelopes, goal progress or
  /// occurrences, which the export does not carry.
  balanceMismatch('move_in.balance_mismatch'),

  /// The store changed while the move was being written — a sync delivered data in between — so
  /// nothing was written.
  changedMeanwhile('move_in.changed_meanwhile'),

  /// The store could not be read or written (facts: none; the store's error is logged by class).
  storeFailed('move_in.store_failed');

  const MoveInRule(this.code);

  /// The stable code, as the server's rule codes are spelled.
  final String code;
}

/// A refused move: the [rule] and the [facts] that say where (see [MoveInRule]).
@immutable
final class MoveInRefusal implements Exception {
  const MoveInRefusal(this.rule, [this.facts = const {}, this.cause]);

  final MoveInRule rule;

  /// Ids, codes, counts and minor-unit amounts only (see [MoveInRule]).
  final Map<String, String> facts;

  /// The store's own error, for [MoveInRule.storeFailed] and [MoveInRule.changedMeanwhile].
  final ZenError? cause;

  @override
  String toString() => 'MoveInRefusal(${rule.code}, $facts)';
}
