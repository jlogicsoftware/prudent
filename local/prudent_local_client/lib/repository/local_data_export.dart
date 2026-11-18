import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart'
    show Ledger, StoreSnapshot, WireMapper;
import 'package:prudent_proto/generated/prudent/v1/privacy.pb.dart';
import 'package:zen_core/zen_core.dart';

/// The person's data copy: the local counterpart of ADR-071's export (plan unit 9, ADR-100 T14).
///
/// It is the server's document (`DataExport`, format version 1), built from this device's store, so
/// a copy saved here reads like one the server made — and could be read back by unit 10b the same
/// way. What it holds, and why some parts are empty:
///
/// - **settings, accounts, categories, records** come from the [Ledger], exactly as the screens read
///   them: a transfer as its two legs, as the server lists it; balances derived, settled values only
///   (ADR-113). A record two devices disagree about is in it as the store shows it, because the copy
///   is of what the person has, not of a figure.
/// - **record import keys** (ADR-110): each imported record's statement key beside it.
/// - **plans, budgets, carry-over resets, goals and goal allocations** are mapped from the store as
///   they are held (units 6a and 6b).
/// - **occurrences** stay empty: an occurrence is read from its plan's schedule and never stored
///   (ADR-119). **Occurrence states** — skipped dates and reminder-read marks — are stored but not in
///   this copy yet: the server's document carries them on its `occurrences` rows, which this copy
///   leaves empty (jlogicsoftware/prudent#288).
/// - **profile, import sessions and import rows** stay empty: there is no sign-in, and import
///   sessions are device-only and never leave the device (ADR-100 T12, ADR-114).
///
/// The copy is plaintext. The screen that saves it warns first and never uses the clipboard
/// (ADR-100 T14).
final class LocalDataExport {
  /// The format version the server writes (`PrudentDataExporter.FORMAT_VERSION`).
  static const int formatVersion = 1;

  /// The clock; tests replace it.
  final DateTime Function() now;

  const LocalDataExport({this.now = DateTime.now});

  /// The document, or the store's error when something cannot be read — never a partial copy that
  /// reads as complete.
  Future<ZenResult<DataExport>> build(Ledger ledger) async {
    final out = DataExport(
      formatVersion: formatVersion,
      exportedAtMs: Int64(now().toUtc().millisecondsSinceEpoch),
    );
    switch (await ledger.getSettings()) {
      case ZenSuccess(:final data):
        out.settings = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    switch (await ledger.listAccounts()) {
      case ZenSuccess(:final data):
        out.accounts.addAll(data.value.accounts);
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    switch (await ledger.listCategories()) {
      case ZenSuccess(:final data):
        out.categories.addAll(data.categories);
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    switch (await ledger.listRecords()) {
      case ZenSuccess(:final data):
        out.records.addAll(data.records);
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final StoreSnapshot snapshot;
    switch (StoreSnapshot.read(ledger.store)) {
      case ZenSuccess(:final data):
        snapshot = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final records = snapshot.records.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final record in records) {
      if (!record.hasImportKey()) continue;
      out.recordImportKeys.add(
        ExportImportKey(
          recordId: record.id,
          fingerprint: record.importKey.fingerprint,
          occurrence: record.importKey.occurrence,
        ),
      );
    }
    out.plans.addAll(_sorted(snapshot.plans).map(WireMapper.planToWire));
    out.budgets.addAll(_sorted(snapshot.budgets).map(WireMapper.budgetToWire));
    out.carryOverResets.addAll(
      _sorted(snapshot.budgetResets).map(WireMapper.resetToWire),
    );
    out.goals.addAll(_sorted(snapshot.goals).map(WireMapper.goalToWire));
    out.goalAllocations.addAll(
      _sorted(snapshot.goalAllocations).map(WireMapper.allocationToWire),
    );
    return ZenResult.ok(out);
  }

  static List<T> _sorted<T>(Map<String, T> byId) => [
    for (final id in byId.keys.toList()..sort()) byId[id] as T,
  ];
}
