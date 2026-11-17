import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:meta/meta.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:zen_core/zen_core.dart';

import '../../generated/prudent_local/v1/imports.pb.dart';
import '../../generated/prudent_local/v1/store.pb.dart';
import '../integrity/checks/category_kind_check.dart';
import '../ledger/ledger.dart';
import '../ledger/ledger_errors.dart';
import '../ledger/ledger_view.dart';
import '../prudent_local_store.dart';
import '../write_expect.dart';
import 'import_mapper.dart';
import 'import_text.dart';

/// Statement import on one device (unit 8b of `docs/implemented-plans/PRUDENT-LOCAL-PLAN.md`, ADR-114): the
/// server's `ImportWorkflow`, `ImportDuplicateStage` and `LedgerImportCommitter`, check for check
/// and in their order, over the ledger's store, whose `import_sessions` collection is device-only
/// (jZenDev/jZen#252): a session never reaches another device, yet it is written in one `writeAll`
/// with the ledger records its commit writes.
///
/// - **Parse** ([create]) is the only way a session comes to exist: the upload bounds, the format,
///   the open-session bound, the destination, then the whole file (unit 8a), and only then one
///   PARSED session. The bytes are an argument to the importer and go nowhere else.
/// - **Preview** ([preview]) needs PARSED or PREVIEWED, validates the destination, resets the
///   duplicates, keys every row that is not rejected for the destination (ADR-091) and marks the
///   rows whose key a ledger record of that account already holds; it may be repeated.
/// - **Commit** ([commit]) needs PREVIEWED, the destination checked again, and the accepted count
///   the person saw. It writes every row as one `writeAll` of the ledger (jZenDev/jZen#232): all or
///   nothing. Record ids derive from the row keys, so two devices that commit one statement end with
///   each row once. A repeated commit answers the stored counts.
///
/// **A rule checked before a write holds when it runs** (jZenDev/jZen#251). Every session write
/// carries an `expect` that the session is still the one this operation read; the commit's batch
/// carries one on each record (it must still be absent) and one on the session that checks the
/// destination, the categories and the duplicates again against the store as it stands in the
/// write's turn — after any sync already queued — and refuses the whole batch if anything changed.
/// On one device the workflow is also serialised: one operation at a time, as the server's row
/// lock makes it.
///
/// Every answer is a [ZenResult]. A refusal carries the server's status and, where the server's
/// message is a rule code with rows (`The statement was rejected at row 3 (amount.invalid).`), that
/// message word for word, which is all the shared screens read (`ImportFailure`). No refusal and no
/// error carries statement text.
final class ImportWorkflow {
  /// The format ids that can be named in a request (`ImportFormats.ids`), sorted.
  static const List<String> formats = [ErsteStatementImporter.formatId];

  /// `ImportSessionResource.MAX_LIST_LIMIT`.
  static const int maxListLimit = 100;

  /// The ledger the commit writes to; the destination and the categories are read from it.
  final PrudentLocalStore ledger;

  /// `prudent.import.max-open-sessions`.
  final int maxOpenSessions;

  /// `prudent.import.max-rows`.
  final int maxRows;

  /// `prudent.import.session-ttl`.
  final Duration sessionTtl;

  final int Function() _nowMs;
  final CivilDate Function() _today;

  /// What a test injects into a commit; null outside a test.
  @visibleForTesting
  final ImportFaults? faults;

  Future<void> _tail = Future<void>.value();

  /// [nowMs] is the wall clock in milliseconds; [today] is the date the importer's range check is
  /// measured from, by default the clock's UTC date, as the server's (`Clock.systemUTC()`).
  ImportWorkflow({
    required this.ledger,
    required int Function() nowMs,
    CivilDate Function()? today,
    this.maxOpenSessions = 10,
    this.maxRows = StatementBounds.defaultMaxRows,
    this.sessionTtl = const Duration(hours: 24),
    this.faults,
  }) : _nowMs = nowMs,
       _today = today ?? (() => _utcDate(nowMs()));

  static CivilDate _utcDate(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String two(int n) => n.toString().padLeft(2, '0');
    return CivilDate.parse('${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}');
  }

  // ── List and read ───────────────────────────────────────────────────────────────────────────

  /// `ImportSessionResource.list` (row 8.24): newest first, then by id, optionally of one [state]
  /// named exactly (`PARSED` … `EXPIRED`), at most [limit] (1–100), without rows.
  Future<ZenResult<wire.ListImportSessionsResponse>> list({String? state, int limit = 50}) =>
      _serial(() async {
        ImportPhase? phase;
        if (state != null && !javaIsBlank(state)) {
          phase =
              _phaseNamed[state] ??
              (throw const Refusal.invalid(
                '8.24',
                'State must be PARSED, PREVIEWED, COMMITTED, DISCARDED or EXPIRED.',
              ));
        }
        if (limit < 1 || limit > maxListLimit) {
          throw const Refusal.invalid('8.24', 'Limit must be between 1 and $maxListLimit.');
        }
        final all = _all();
        final chosen = [
          for (final s in all)
            if (phase == null || s.phase == phase) s,
        ]..sort(_newestFirst);
        return wire.ListImportSessionsResponse(
          sessions: [for (final s in chosen.take(limit)) ImportMapper.session(s)],
        );
      });

  /// `ImportWorkflow.get`: one session, with its rows while it holds them. A session whose time has
  /// run out is expired here, so a read never shows rows that should already be gone.
  Future<ZenResult<wire.ImportSession>> get(String id) => _serial(() async {
    var session = _load(id);
    final now = _nowMs();
    if (_holdsRows(session) && _isDue(session, now)) {
      session = await _put(_ended(session, ImportPhase.IMPORT_PHASE_EXPIRED, now), over: session);
    }
    return ImportMapper.session(session, withRows: _holdsRows(session));
  });

  // ── Parse ───────────────────────────────────────────────────────────────────────────────────

  /// PARSE (`ImportWorkflow.create`, rows 8.1–8.6, 8.21, 8.25): runs the named importer and, only
  /// if it accepts the statement, opens a session. A refusal writes nothing.
  Future<ZenResult<wire.ImportSession>> create(wire.CreateImportSessionRequest request) =>
      _serial(() async {
        final accountId = request.hasAccountId() ? _idInBody(request.accountId, 'account') : null;
        final content = Uint8List.fromList(request.content);
        try {
          StatementBounds.checkUpload(content);
        } on ImportRejection catch (rejected) {
          throw Refusal.invalid('8.4', rejected.message);
        }
        if (!formats.contains(request.formatId)) {
          // The requested id is not echoed: it is the caller's text.
          throw Refusal.invalid(
            '8.25',
            'Unsupported import format. Supported formats: ${formats.join(', ')}.',
          );
        }
        final now = _nowMs();
        var open = 0;
        for (final s in _all()) {
          if (_holdsRows(s) && !_isDue(s, now)) open++;
        }
        if (open >= maxOpenSessions) {
          throw const Refusal.conflict(
            '8.4',
            'Too many import sessions are open. Commit or discard one before uploading another.',
          );
        }
        final view = LedgerView.read(ledger);
        if (accountId != null && !view.accounts.containsKey(accountId)) {
          throw Refusal.invalid('8.5', ImportRejection(ImportRule.accountNotFound).message);
        }

        final ParsedStatement parsed;
        try {
          parsed = ErsteStatementImporter.parse(content, today: _today());
          StatementBounds.validate(
            ErsteStatementImporter.formatId,
            parsed,
            maxRows: maxRows,
            stableExternalId: ErsteStatementImporter.stableExternalId,
          );
          if (accountId != null) {
            // The statement is parsed, so the currency is known and the destination can be checked
            // in full. The preview checks it again whenever it changes.
            final account = _requireDestination(view, accountId, parsed.currency, atCommit: false);
            ErsteStatementImporter.checkDestination(parsed.accountIdentity, account.accountNumber);
          }
        } on ImportRejection catch (rejected) {
          // The message holds a rule code and row numbers and nothing else, by construction.
          throw Refusal.invalid('8.6', rejected.message);
        }

        final session = LocalImportSession(
          id: ledger.newId(),
          formatId: ErsteStatementImporter.formatId,
          phase: ImportPhase.IMPORT_PHASE_PARSED,
          currency: parsed.currency,
          createdAtMs: Int64(now),
          phaseChangedAtMs: Int64(now),
          expiresAtMs: Int64(now + sessionTtl.inMilliseconds),
          rows: [for (final row in parsed.rows) _rowOf(row)],
        );
        if (accountId != null) session.accountId = accountId;
        if (parsed.accountIdentity case final identity?) session.statementIdentity = identity;
        _recount(session);
        return ImportMapper.session(await _put(session, over: null), withRows: true);
      });

  // ── Preview ─────────────────────────────────────────────────────────────────────────────────

  /// PREVIEW (`ImportWorkflow.preview` with `ImportDuplicateStage`, rows 8.1, 8.5, 8.10): PARSED or
  /// PREVIEWED → PREVIEWED, after the destination is validated (the one named now, else the one
  /// already chosen) and the rows are classified from scratch for it.
  Future<ZenResult<wire.ImportSession>> preview(
    String id,
    wire.PreviewImportSessionRequest request,
  ) => _serial(() async {
    final named = request.hasAccountId() ? _idInBody(request.accountId, 'account') : null;
    final current = _load(id);
    final now = _nowMs();
    if (!_holdsRows(current)) {
      throw Refusal.conflict(
        '8.1',
        'Only a parsed or previewed import session can be previewed; this one is '
            '${_name(current.phase)}.',
      );
    }
    _requireNotDue(current, now);
    final session = current.deepCopy();
    final view = LedgerView.read(ledger);
    final destination = named ?? (session.hasAccountId() ? session.accountId : null);
    if (destination != null) {
      _checkDestination(view, session, destination, atCommit: false);
      session.accountId = destination;
    }
    for (final row in session.rows) {
      if (row.kind == ImportRowKind.IMPORT_ROW_KIND_DUPLICATE) {
        row
          ..kind = ImportRowKind.IMPORT_ROW_KIND_ACCEPTED
          ..clearDuplicateCode()
          ..includeDuplicate = false;
      }
    }
    _markDuplicates(view, session);
    _recount(session);
    _transition(session, ImportPhase.IMPORT_PHASE_PREVIEWED, now);
    return ImportMapper.session(await _put(session, over: current), withRows: true);
  });

  /// `ImportDuplicateStage.apply`: clears every key; with a destination, keys every row that is not
  /// rejected (a row marked by another stage still occupies its occurrence) and marks each accepted
  /// row whose key a record of the destination already holds.
  static void _markDuplicates(LedgerView view, LocalImportSession session) {
    for (final row in session.rows) {
      row
        ..clearFingerprint()
        ..clearOccurrence();
    }
    if (!session.hasAccountId()) return;
    final keyed = [
      for (final row in session.rows)
        if (row.kind != ImportRowKind.IMPORT_ROW_KIND_REJECTED) row,
    ];
    final keys = RowFingerprints.keys([
      for (final row in keyed)
        RowFingerprints.fingerprint(
          session.accountId,
          session.formatId,
          session.currency,
          FingerprintFields(
            transactionDate: CivilDate.parse(row.transactionDate),
            amountMinor: row.amountMinor.toInt(),
            description: row.hasDescription() ? ImportText.read(row.description) : null,
            counterparty: row.hasCounterparty() ? ImportText.read(row.counterparty) : null,
            counterpartyAccount: row.hasCounterpartyAccount()
                ? ImportText.read(row.counterpartyAccount)
                : null,
          ),
        ),
    ]);
    final held = _heldKeys(view, session.accountId);
    for (var i = 0; i < keyed.length; i++) {
      final row = keyed[i]
        ..fingerprint = keys[i].fingerprint
        ..occurrence = keys[i].occurrence;
      if (row.kind == ImportRowKind.IMPORT_ROW_KIND_ACCEPTED && held.contains(keys[i])) {
        row
          ..kind = ImportRowKind.IMPORT_ROW_KIND_DUPLICATE
          ..duplicateCode = ImportRule.alreadyImported;
      }
    }
  }

  /// The keys the ledger records of [accountId] hold (`RecordEntity.importedKeys`), on any side of a
  /// conflict: a key is immutable, so every side of one record carries the same.
  static Set<RowKey> _heldKeys(LedgerView view, String accountId) => {
    for (final record in view.recordValues())
      if (record.hasImportKey() && record.posting.accountId == accountId)
        RowKey(record.importKey.fingerprint, record.importKey.occurrence),
  };

  // ── Row decisions and defaults ──────────────────────────────────────────────────────────────

  /// ROW DECISION (`ImportWorkflow.updateRow`, rows 8.12, 8.13): a category (an empty string
  /// clears it), a note of at most 500 characters, or whether to include a DUPLICATE row. A
  /// rejected row takes no decision. Answers the row and the counts, not the session.
  Future<ZenResult<wire.UpdateImportRowResponse>> updateRow(
    String id,
    int rowNumber,
    wire.UpdateImportRowRequest request,
  ) => _serial(() async {
    String? categoryId;
    var clearCategory = false;
    if (request.hasCategoryId()) {
      if (request.categoryId.isEmpty) {
        clearCategory = true;
      } else {
        categoryId = _idInBody(request.categoryId, 'category');
      }
    }
    final current = _load(id);
    final now = _nowMs();
    if (!_holdsRows(current)) {
      throw Refusal.conflict(
        '8.12',
        'An import session that is ${_name(current.phase)} holds no rows to change.',
      );
    }
    _requireNotDue(current, now);
    final session = current.deepCopy();
    final row = session.rows.where((r) => r.rowNumber == rowNumber).firstOrNull;
    if (row == null) throw const Refusal.notFound('8.12', 'No such import row.');
    if (row.kind == ImportRowKind.IMPORT_ROW_KIND_REJECTED) {
      throw Refusal.conflict('8.12', 'Row $rowNumber was rejected and cannot be changed.');
    }
    var note = row.hasNote() ? row.note : null;
    if (request.hasNote()) {
      try {
        note = TextRules.trimmedOptionalNote(request.note);
      } on Refusal {
        throw const Refusal.invalid('8.12', 'A note can be at most 500 characters.');
      }
    }
    final include = request.hasIncludeDuplicate() ? request.includeDuplicate : null;
    if (include == true && row.kind != ImportRowKind.IMPORT_ROW_KIND_DUPLICATE) {
      throw Refusal.invalid(
        '8.12',
        'Only a row marked as a duplicate can be included; row $rowNumber is not one.',
      );
    }
    if (categoryId != null) {
      row.categoryId = _requireCategoryFor(
        LedgerView.read(ledger),
        categoryId,
        row.amountMinor.toInt(),
      );
    } else if (clearCategory) {
      row.clearCategoryId();
    }
    if (note == null) {
      row.clearNote();
    } else {
      row.note = note;
    }
    if (include != null && include != row.includeDuplicate) {
      row.includeDuplicate = include;
      _recount(session);
    }
    await _put(session, over: current);
    return wire.UpdateImportRowResponse(
      row: ImportMapper.row(session.id, row),
      acceptedRows: session.acceptedRows,
      duplicateRows: session.duplicateRows,
      rejectedRows: session.rejectedRows,
    );
  });

  /// DEFAULTS (`ImportWorkflow.setDefaults`, row 8.13): the category a row with none of its own is
  /// written under, per direction. Each is validated like a row's category and again at commit.
  Future<ZenResult<wire.ImportSession>> setDefaults(
    String id,
    wire.SetImportDefaultsRequest request,
  ) => _serial(() async {
    String? expense;
    var clearExpense = false;
    if (request.hasDefaultExpenseCategoryId()) {
      if (request.defaultExpenseCategoryId.isEmpty) {
        clearExpense = true;
      } else {
        expense = _idInBody(request.defaultExpenseCategoryId, 'category');
      }
    }
    String? income;
    var clearIncome = false;
    if (request.hasDefaultIncomeCategoryId()) {
      if (request.defaultIncomeCategoryId.isEmpty) {
        clearIncome = true;
      } else {
        income = _idInBody(request.defaultIncomeCategoryId, 'category');
      }
    }
    final current = _load(id);
    final now = _nowMs();
    if (!_holdsRows(current)) {
      throw Refusal.conflict(
        '8.13',
        'An import session that is ${_name(current.phase)} holds no rows to categorise.',
      );
    }
    _requireNotDue(current, now);
    final session = current.deepCopy();
    final view = LedgerView.read(ledger);
    if (expense != null) {
      // -1 and +1 stand for "an expense" and "an income" in the kind check.
      session.defaultExpenseCategoryId = _requireCategoryFor(view, expense, -1);
    } else if (clearExpense) {
      session.clearDefaultExpenseCategoryId();
    }
    if (income != null) {
      session.defaultIncomeCategoryId = _requireCategoryFor(view, income, 1);
    } else if (clearIncome) {
      session.clearDefaultIncomeCategoryId();
    }
    return ImportMapper.session(await _put(session, over: current));
  });

  /// DISCARD (`ImportWorkflow.discard`): the person throws the session away; its rows go with it.
  Future<ZenResult<wire.ImportSession>> discard(String id) => _serial(() async {
    final session = _load(id);
    return ImportMapper.session(
      await _put(_ended(session, ImportPhase.IMPORT_PHASE_DISCARDED, _nowMs()), over: session),
    );
  });

  /// The sweep (`ImportWorkflow.expireDue`, row 8.3): expires every session whose time has run out and deletes its rows. The Local app runs it at
  /// launch and on a timer (unit 9). Answers how many sessions it expired.
  Future<ZenResult<int>> expireDue() => _serial(() async {
    final now = _nowMs();
    var expired = 0;
    for (final s in _all()) {
      if (_holdsRows(s) && _isDue(s, now)) {
        await _put(_ended(s, ImportPhase.IMPORT_PHASE_EXPIRED, now), over: s);
        expired++;
      }
    }
    return expired;
  });

  // ── Commit ──────────────────────────────────────────────────────────────────────────────────

  /// COMMIT (`ImportWorkflow.commit` with `LedgerImportCommitter`, rows 8.14–8.18): PREVIEWED →
  /// COMMITTED once every writable row is in the ledger, written as one batch. [confirmedAcceptedRows]
  /// is how many rows the person saw accepted; any other number means the review is not this
  /// session, and nothing is written. A repeat of a commit that went through answers its counts.
  Future<ZenResult<wire.ImportSession>> commit(
    String id,
    wire.CommitImportSessionRequest request,
  ) => _serial(() async {
    final confirmed = request.confirmedAcceptedRows;
    final session = _load(id);
    final now = _nowMs();
    if (session.phase == ImportPhase.IMPORT_PHASE_COMMITTED) {
      // A retry of a commit that went through: the same answer, not an error and not a write.
      if (confirmed != session.acceptedRows) {
        throw const Refusal.conflict(
          '8.17',
          'This import session is already committed with a different number of rows.',
        );
      }
      return ImportMapper.session(session);
    }
    if (session.phase == ImportPhase.IMPORT_PHASE_PARSED) {
      throw const Refusal.conflict('8.1', 'Preview the import session before committing it.');
    }
    if (session.phase != ImportPhase.IMPORT_PHASE_PREVIEWED) {
      throw Refusal.conflict(
        '8.1',
        'Only a previewed import session can be committed; this one is ${_name(session.phase)}.',
      );
    }
    _requireNotDue(session, now);
    if (!session.hasAccountId()) {
      throw const Refusal.conflict(
        '8.5',
        'Choose a destination account for the import before committing it.',
      );
    }
    final view = LedgerView.read(ledger);
    _checkDestination(view, session, session.accountId, atCommit: true);
    final accepted = [
      for (final row in session.rows)
        if (_isWritable(row)) row,
    ];
    if (confirmed != accepted.length) {
      throw const Refusal.conflict(
        '8.15',
        'The confirmed row count does not match the session\'s accepted rows. Review the preview '
            'again.',
      );
    }

    final plan = _plan(view, session, accepted);
    await faults?.beforeWrite?.call();
    final completed = _ended(session, ImportPhase.IMPORT_PHASE_COMMITTED, now)
      ..committedWritten = plan.written
      ..committedAlreadyImported = plan.alreadyImported;
    // The records and the completed session as one write (jZenDev/jZen#232, #252): all of it or none
    // of it, even across a power loss. Each part says what must still hold when the write takes its
    // turn (#251): the record is still absent, and the session, its destination, its categories and
    // the keys the ledger holds are still what this plan was made from.
    final batch = StoreBatch(ledger);
    for (final record in plan.records) {
      batch.putRecord(record, expect: WriteExpects.asRead(null, changed: () => _changedMeanwhile));
    }
    batch.putImportSession(
      completed,
      expect: (current) => _stillHolds(current, session, accepted, plan),
    );
    readOrThrow(await ledger.writeAll(batch));
    return ImportMapper.session(completed);
  });

  /// The commit's precondition, run inside the batch's turn: [current] is still the [session] the
  /// plan was made from, and planning it again over the ledger as it stands now gives the same
  /// records — so a sync that arrived since (an account deleted or renumbered, a category archived,
  /// the same statement's records from another device) refuses the commit, which writes nothing.
  ZenError? _stillHolds(
    LocalImportSession? current,
    LocalImportSession session,
    List<LocalImportRow> accepted,
    _Plan plan,
  ) {
    if (current != session) return _changedMeanwhile;
    try {
      final view = LedgerView.read(ledger);
      _checkDestination(view, session, session.accountId, atCommit: true);
      final again = _plan(view, session, accepted);
      final same =
          again.written == plan.written &&
          again.alreadyImported == plan.alreadyImported &&
          again.records.length == plan.records.length &&
          [for (var i = 0; i < plan.records.length; i++) again.records[i] == plan.records[i]]
              .every((same) => same);
      return same ? null : _changedMeanwhile;
    } on Refusal catch (refusal) {
      return LedgerErrors.of(refusal);
    } on LedgerReadFailure catch (failure) {
      return failure.error;
    } on StateError catch (bug) {
      return ZenUnknownError(bug.message);
    }
  }

  /// What a write answers when what it was checked against changed before it ran.
  static final ZenError _changedMeanwhile = LedgerErrors.of(
    const Refusal.conflict(
      '8.16',
      'The ledger or the import changed while this was being done. Review the import again.',
    ),
  );

  /// `LedgerImportCommitter.commit` up to its first write: every refusal it can make, then the
  /// records of every row to write and the counts it answers, in its order — the rows not included
  /// as duplicates first (a key the account already holds is counted, not written), then each
  /// included duplicate under the next free occurrence of its fingerprint.
  _Plan _plan(LedgerView view, LocalImportSession session, List<LocalImportRow> accepted) {
    final records = <Record>[];
    if (accepted.isEmpty) return _Plan(records, 0, 0);
    final uncategorised = accepted.where((row) => _categoryOf(session, row) == null).length;
    if (uncategorised > 0) {
      throw Refusal.conflict(
        '8.14',
        '$uncategorised row(s) have no category yet. Choose a category for every row, or a default '
            'category for expenses and for income, before committing.',
      );
    }
    _requireUsableCategories(view, session, accepted);
    for (final row in accepted) {
      if (!row.hasFingerprint() || !row.hasOccurrence()) {
        // A PREVIEWED session with a destination always has keys; a row without one would be
        // written unrecognisable, so it is a bug, not the person's mistake.
        throw StateError('Row ${row.rowNumber} of an import session has no key.');
      }
    }
    final held = _heldKeys(view, session.accountId);
    var written = 0;
    var alreadyImported = 0;
    final forced = <LocalImportRow>[];
    for (final row in accepted) {
      if (row.includeDuplicate) {
        forced.add(row);
        continue;
      }
      final key = RowKey(row.fingerprint, row.occurrence);
      if (held.contains(key)) {
        alreadyImported++;
        continue;
      }
      records.add(_record(view, session, row, key));
      held.add(key);
      written++;
    }
    // Forced rows last, so the next free occurrence also steps over the rows written just above.
    final highest = <String, int>{};
    for (final key in held) {
      highest.update(
        key.fingerprint,
        (n) => n > key.occurrence ? n : key.occurrence,
        ifAbsent: () => key.occurrence,
      );
    }
    for (final row in forced) {
      final occurrence = highest.update(row.fingerprint, (n) => n + 1, ifAbsent: () => 1);
      records.add(_record(view, session, row, RowKey(row.fingerprint, occurrence)));
      written++;
    }
    return _Plan(records, written, alreadyImported);
  }

  /// The record of [row] under [key]. Whatever the ledger
  /// refuses, the answer names the rule and the row, never the ledger's sentence, which can quote a
  /// value it was given — and a row's values come from the statement.
  Record _record(LedgerView view, LocalImportSession session, LocalImportRow row, RowKey key) {
    final Record record;
    try {
      faults?.beforeRow?.call(row.rowNumber);
      record = Ledger.importedRecord(
        view,
        accountId: session.accountId,
        currency: session.currency,
        key: key,
        title: _titleOf(row),
        amountMinor: row.amountMinor.toInt(),
        date: row.transactionDate,
        categoryId: _categoryOf(session, row)!,
        payee: row.hasCounterparty() ? ImportText.read(row.counterparty) : null,
        note: row.hasNote() ? row.note : null,
      );
    } on Refusal {
      throw Refusal.conflict(
        '8.18',
        ImportRejection(ImportRule.commitRowRefused, row.rowNumber).message,
      );
    }
    return record;
  }

  /// `LedgerImportCommitter.requireUsableCategories`: every row whose category is gone, archived or
  /// for the other direction, named by rule and rows before anything is written.
  static void _requireUsableCategories(
    LedgerView view,
    LocalImportSession session,
    List<LocalImportRow> accepted,
  ) {
    final unusable = <int>[];
    for (final row in accepted) {
      final category = view.categories[_categoryOf(session, row)];
      if (category == null ||
          category.archived ||
          !CategoryKindCheck.canFile(category.kind, row.amountMinor.toInt())) {
        unusable.add(row.rowNumber);
      }
    }
    if (unusable.isNotEmpty) {
      throw Refusal.conflict(
        '8.18',
        ImportRejection.rows(
          ImportRule.commitCategoryUnavailable,
          unusable.take(ErsteStatementImporter.maxReportedRows).toList(),
          unusable.length,
        ).message,
      );
    }
  }

  /// The title a record gets: the description, else the counterparty, else
  /// `LedgerImportCommitter.FALLBACK_TITLE`.
  static String _titleOf(LocalImportRow row) {
    for (final text in [
      if (row.hasDescription()) ImportText.read(row.description),
      if (row.hasCounterparty()) ImportText.read(row.counterparty),
    ]) {
      if (!javaIsBlank(text)) return text;
    }
    return fallbackTitle;
  }

  /// `LedgerImportCommitter.FALLBACK_TITLE`.
  static const fallbackTitle = 'Imported transaction';

  /// The category a row is written under: its own, else the session's default for its direction.
  static String? _categoryOf(LocalImportSession session, LocalImportRow row) {
    if (row.hasCategoryId()) return row.categoryId;
    if (row.amountMinor < 0) {
      return session.hasDefaultExpenseCategoryId() ? session.defaultExpenseCategoryId : null;
    }
    return session.hasDefaultIncomeCategoryId() ? session.defaultIncomeCategoryId : null;
  }

  // ── Destination and categories ──────────────────────────────────────────────────────────────

  /// Every rule about a destination account (`ImportWorkflow.checkDestination`): the account exists,
  /// is active and holds the session's currency, and the importer accepts the statement's identity
  /// for it. A 400 when the account came from a request; a 409 at the commit, where the request was
  /// fine and the world changed (`commit.account_unavailable`, or the importer's own rule).
  void _checkDestination(
    LedgerView view,
    LocalImportSession session,
    String accountId, {
    required bool atCommit,
  }) {
    final account = _requireDestination(view, accountId, session.currency, atCommit: atCommit);
    if (!formats.contains(session.formatId)) {
      throw const Refusal.conflict(
        '8.5',
        'The importer for this session\'s format is no longer available.',
      );
    }
    try {
      ErsteStatementImporter.checkDestination(
        session.hasStatementIdentity() ? session.statementIdentity : null,
        account.accountNumber,
      );
    } on ImportRejection catch (rejected) {
      throw atCommit
          ? Refusal.conflict('8.5', rejected.message)
          : Refusal.invalid('8.5', rejected.message);
    }
  }

  /// `ImportWorkflow.requireDestination`: the account exists, is active and holds [currency].
  static Account _requireDestination(
    LedgerView view,
    String accountId,
    String currency, {
    required bool atCommit,
  }) {
    Refusal refuse(String message) => atCommit
        ? Refusal.conflict('8.5', ImportRejection(ImportRule.commitAccountUnavailable).message)
        : Refusal.invalid('8.5', message);
    final account = view.accounts[accountId];
    if (account == null) throw refuse(ImportRejection(ImportRule.accountNotFound).message);
    if (!account.active) throw refuse('The destination account is inactive.');
    if (!view.holds(account.id, currency)) {
      throw refuse(
        'The destination account does not hold $currency. Add the currency to it first.',
      );
    }
    return account;
  }

  /// `ImportWorkflow.requireCategoryFor`: an existing category (400), not archived (409), that can
  /// file an amount of [amountMinor]'s sign (400).
  static String _requireCategoryFor(LedgerView view, String categoryId, int amountMinor) {
    final category = view.categories[categoryId];
    if (category == null) throw const Refusal.invalid('8.12', 'No such category.');
    if (category.archived) {
      throw const Refusal.conflict(
        '8.12',
        'This category is archived. Restore it, or choose another category.',
      );
    }
    if (!CategoryKindCheck.canFile(category.kind, amountMinor)) {
      throw const Refusal.invalid('8.12', 'This category is for the other direction.');
    }
    return category.id;
  }

  // ── The session ─────────────────────────────────────────────────────────────────────────────

  static const _phaseNamed = {
    'PARSED': ImportPhase.IMPORT_PHASE_PARSED,
    'PREVIEWED': ImportPhase.IMPORT_PHASE_PREVIEWED,
    'COMMITTED': ImportPhase.IMPORT_PHASE_COMMITTED,
    'DISCARDED': ImportPhase.IMPORT_PHASE_DISCARDED,
    'EXPIRED': ImportPhase.IMPORT_PHASE_EXPIRED,
  };

  /// The server's name of [phase], as its messages spell it.
  static String _name(ImportPhase phase) =>
      _phaseNamed.entries.firstWhere((e) => e.value == phase).key;

  /// `ImportState.successors`: the whole state machine.
  static const _successors = {
    ImportPhase.IMPORT_PHASE_PARSED: {
      ImportPhase.IMPORT_PHASE_PREVIEWED,
      ImportPhase.IMPORT_PHASE_DISCARDED,
      ImportPhase.IMPORT_PHASE_EXPIRED,
    },
    ImportPhase.IMPORT_PHASE_PREVIEWED: {
      ImportPhase.IMPORT_PHASE_PREVIEWED,
      ImportPhase.IMPORT_PHASE_COMMITTED,
      ImportPhase.IMPORT_PHASE_DISCARDED,
      ImportPhase.IMPORT_PHASE_EXPIRED,
    },
  };

  /// `ImportSessionEntity.transitionTo`: the only writer of the phase after creation.
  static void _transition(LocalImportSession session, ImportPhase target, int now) {
    if (!(_successors[session.phase]?.contains(target) ?? false)) {
      throw Refusal.conflict(
        '8.1',
        'An import session that is ${_name(session.phase)} cannot be made ${_name(target)}.',
      );
    }
    session
      ..phase = target
      ..phaseChangedAtMs = Int64(now);
  }

  /// `ImportWorkflow.end`: a terminal phase, and everything the session held is deleted — its rows,
  /// the statement's identity token and the default categories.
  static LocalImportSession _ended(LocalImportSession session, ImportPhase terminal, int now) {
    final ended = session.deepCopy();
    _transition(ended, terminal, now);
    ended
      ..rows.clear()
      ..clearStatementIdentity()
      ..clearDefaultExpenseCategoryId()
      ..clearDefaultIncomeCategoryId();
    return ended;
  }

  static bool _holdsRows(LocalImportSession s) =>
      s.phase == ImportPhase.IMPORT_PHASE_PARSED || s.phase == ImportPhase.IMPORT_PHASE_PREVIEWED;

  static bool _isDue(LocalImportSession s, int now) => s.expiresAtMs.toInt() <= now;

  static void _requireNotDue(LocalImportSession session, int now) {
    if (_isDue(session, now)) {
      throw const Refusal.conflict(
        '8.3',
        'This import session has expired. Upload the statement again.',
      );
    }
  }

  static bool _isWritable(LocalImportRow row) =>
      row.kind == ImportRowKind.IMPORT_ROW_KIND_ACCEPTED ||
      (row.kind == ImportRowKind.IMPORT_ROW_KIND_DUPLICATE && row.includeDuplicate);

  /// `ImportSessionEntity.recount`: an included duplicate is written, so it counts as accepted.
  static void _recount(LocalImportSession session) {
    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;
    for (final row in session.rows) {
      if (_isWritable(row)) accepted++;
      if (row.kind == ImportRowKind.IMPORT_ROW_KIND_DUPLICATE && !row.includeDuplicate) {
        duplicates++;
      }
      if (row.kind == ImportRowKind.IMPORT_ROW_KIND_REJECTED) rejected++;
    }
    session
      ..acceptedRows = accepted
      ..duplicateRows = duplicates
      ..rejectedRows = rejected;
  }

  static LocalImportRow _rowOf(ParsedRow row) {
    if (row.rejectionCode case final code?) {
      return LocalImportRow(
        rowNumber: row.rowNumber,
        kind: ImportRowKind.IMPORT_ROW_KIND_REJECTED,
        rejectionCode: code,
      );
    }
    final out = LocalImportRow(
      rowNumber: row.rowNumber,
      kind: ImportRowKind.IMPORT_ROW_KIND_ACCEPTED,
      transactionDate: row.transactionDate.toString(),
      amountMinor: Int64(row.amountMinor!),
    );
    if (row.bookingDate case final v?) out.bookingDate = v.toString();
    if (row.description case final v?) out.description = ImportText.write(v);
    if (row.counterparty case final v?) out.counterparty = ImportText.write(v);
    if (row.counterpartyAccount case final v?) out.counterpartyAccount = ImportText.write(v);
    if (row.externalId case final v?) out.externalId = ImportText.write(v);
    if (row.hintCode case final v?) out.hintCode = v;
    return out;
  }

  static int _newestFirst(LocalImportSession a, LocalImportSession b) {
    final byTime = b.createdAtMs.compareTo(a.createdAtMs);
    return byTime != 0 ? byTime : LocalIds.compare(a.id, b.id);
  }

  // ── Plumbing ────────────────────────────────────────────────────────────────────────────────

  List<LocalImportSession> _all() => readOrThrow(ledger.importSessions.list());

  /// The session [id] (404 for a malformed or unknown id, as `Ids.parse` answers).
  LocalImportSession _load(String id) {
    if (!LocalIds.isValid(id)) throw const Refusal.notFound('8.1', 'No such import session.');
    final found = ledger.importSessions.get(id);
    final session = switch (found) {
      ZenSuccess(:final data) => data,
      ZenFailure(:final error) when error is ZenNotFoundError => throw const Refusal.notFound(
        '8.1',
        'No such import session.',
      ),
      ZenFailure(:final error) => throw LedgerReadFailure(error),
    };
    return session;
  }

  /// Writes [session] over [over], the session this operation read (null for a new one), and only
  /// if the store still holds exactly that — the same bytes — when the write takes its turn
  /// (jZenDev/jZen#251, `WriteExpects.asRead` as every Local write, ADR-115).
  Future<LocalImportSession> _put(
    LocalImportSession session, {
    required LocalImportSession? over,
  }) async => readOrThrow(
    await ledger.putImportSession(
      session,
      expect: WriteExpects.asRead(
        over,
        gone: () => _changedMeanwhile,
        changed: () => _changedMeanwhile,
      ),
    ),
  );

  /// A body's id (`Ids.parseInBody`): a malformed one is a 400 that does not echo it.
  static String _idInBody(String id, String what) {
    if (!LocalIds.isValid(id)) throw Refusal.invalid('8.5', 'Not a valid $what id.');
    return id;
  }

  /// Runs one operation after the one before it has finished, as the server's row lock serialises
  /// two requests on one session; a rule's [Refusal] becomes the server-shaped error, a store's error
  /// is returned as it is.
  Future<ZenResult<T>> _serial<T>(Future<T> Function() body) {
    final run = _tail.then((_) => _guard(body));
    // The queue only waits for the operation to end. An error it threw still reaches its caller
    // through `run`; it must not also stop every later operation from starting.
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<ZenResult<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return ZenResult.ok(await body());
    } on Refusal catch (refusal) {
      return ZenResult.err(LedgerErrors.of(refusal));
    } on LedgerReadFailure catch (failure) {
      return ZenResult.err(failure.error);
    } on StateError catch (bug) {
      // An importer or workflow bug. Its message names a format or a row number, never row text.
      return ZenResult.err(ZenUnknownError(bug.message));
    }
  }
}

/// Faults a test injects into a commit, the way the server's tests replace its record writer. Never
/// set outside a test.
@visibleForTesting
final class ImportFaults {
  /// Runs before the record of row [rowNumber] is built; a [Refusal] thrown here is the ledger
  /// refusing that row.
  final void Function(int rowNumber)? beforeRow;

  /// Runs after the commit is planned and before its batch is written: a test changes the store
  /// here, as a sync arriving in between would.
  final Future<void> Function()? beforeWrite;

  const ImportFaults({this.beforeRow, this.beforeWrite});
}

/// The records a commit writes and the counts it answers.
final class _Plan {
  final List<Record> records;
  final int written;
  final int alreadyImported;

  const _Plan(this.records, this.written, this.alreadyImported);
}
