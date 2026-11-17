/// Prudent Local's store model on jZen's `zen_store` (ADR-102, ADR-111).
///
/// - [PrudentLocalStore]: the collections of one open store and the only way to write them
/// - [DerivedIds]: record ids derived from natural keys, so two devices write one record
/// - [StorePolicies]: the per-field merge policies (same-intent times only)
/// - [WireMapper]: store messages to and from the wire messages of `proto/prudent/v1/`
/// - [IntegrityRunner], [IntegrityCheck], [IntegrityIssue]: the rules across records a merge can
///   break, listed after every change and never fixed silently
/// - [PlanLedger]: plans, their occurrences and reminders, with the server's rules, `asOf` passed
///   explicitly (unit 6b, ADR-119)
/// - [Ledger]: accounts, categories, records, transfers, corrections and settings with the server's
///   rules, derived balances and the record list (unit 5, ADR-113); budgets, carry-over resets,
///   goals, envelopes, free money and progress (unit 6a, ADR-116)
/// - [ImportWorkflow]: statement import sessions in a device-only collection, duplicates, and the
///   commit into the ledger as one write (unit 8b, ADR-114)
library;

export 'generated/prudent_local/v1/imports.pb.dart';
export 'generated/prudent_local/v1/store.pb.dart';
export 'src/derived_ids.dart';
export 'src/imports/import_mapper.dart';
export 'src/imports/import_workflow.dart';
export 'src/integrity/checks/archived_goal_money_check.dart';
export 'src/integrity/checks/category_kind_check.dart';
export 'src/integrity/checks/correction_intent_check.dart';
export 'src/integrity/checks/dangling_reference_check.dart';
export 'src/integrity/checks/default_account_check.dart';
export 'src/integrity/checks/duplicate_account_number_check.dart';
export 'src/integrity/checks/envelope_below_zero_check.dart';
export 'src/integrity/checks/held_currency_check.dart';
export 'src/integrity/checks/live_reset_slot_check.dart';
export 'src/integrity/checks/occurrence_skipped_and_paid_check.dart';
export 'src/integrity/checks/repairs_made_apart_check.dart';
export 'src/integrity/integrity_issue.dart';
export 'src/integrity/integrity_runner.dart';
export 'src/integrity/store_snapshot.dart';
export 'src/ledger/ledger.dart';
export 'src/ledger/ledger_errors.dart';
export 'src/ledger/ledger_view.dart' show AccountBalances, Settled;
export 'src/ledger/plan_ledger.dart';
export 'src/ledger/record_query.dart';
export 'src/prudent_local_store.dart';
export 'src/wire_mapper.dart';
