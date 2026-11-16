/// Prudent Local's domain core: the server's rules in pure Dart (ADR-101, ADR-107).
///
/// Every function here reproduces a named method of the Quarkus server and is held to it by golden
/// vectors the server's JVM writes (`test/golden/`). The server is the specification; where Local
/// must differ, the difference is an ADR, not a surprise.
library;

export 'src/account_numbers.dart';
export 'src/civil_date.dart';
export 'src/currencies.dart';
export 'src/currency_totals.dart';
export 'src/goal_arithmetic.dart';
export 'src/imports/erste_csv.dart';
export 'src/imports/erste_statement_importer.dart';
export 'src/imports/import_rules.dart';
export 'src/imports/parsed_statement.dart';
export 'src/imports/row_fingerprints.dart';
export 'src/imports/statement_import.dart';
export 'src/iso4217.dart';
export 'src/java_text.dart';
export 'src/local_ids.dart';
export 'src/minor_units.dart';
export 'src/plans/plan_zones.dart';
export 'src/plans/recurrence_rule.dart';
export 'src/plans/reminder_lead_times.dart';
export 'src/record_types.dart';
export 'src/refusal.dart';
export 'src/spend_windows.dart';
export 'src/text_rules.dart';
