import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';

// The synthetic statement builder of unit 8a, held to the server's by the golden file's digests.
import '../../../prudent_local_core/test/imports/erste_support.dart';

export '../../../prudent_local_core/test/imports/erste_support.dart';

/// The value [result] holds; fails the test with the error otherwise.
T ok<T>(ZenResult<T> result) => switch (result) {
  ZenSuccess(:final data) => data,
  ZenFailure(:final error) => fail('expected success, got ${error.runtimeType}: ${error.message}'),
};

/// The error [result] holds, which must be a refusal with the server's [status]; fails otherwise.
ZenError refused<T>(ZenResult<T> result, int status) => switch (result) {
  ZenSuccess(:final data) => fail('expected a refusal ($status), got $data'),
  ZenFailure(:final error) =>
    LedgerErrors.statusOf(error) == status
        ? error
        : fail(
            'expected $status, got ${error.runtimeType} '
            '(${LedgerErrors.statusOf(error)}): ${error.message}',
          ),
};

/// The synthetic statements of the server's `ImportTestSupport.Erste` (ADR-088: nothing real).
abstract final class Erste {
  /// The statement's own account, in `AccountNumbers` normal form.
  static const account = '00000000000000000000000001';

  /// Another number, for an account that is not the statement's.
  static const otherAccount = '00000000000000000000000099';

  /// The five transaction rows of the base statement: card, BLIK, an incoming own-account transfer,
  /// card, card. Rows 1, 2, 4 and 5 are expenses; row 3 is income.
  static List<List<String>> baseRows() => [
    ErsteStatements.summary(),
    ErsteStatements.card('12-03-2026', '10-03-2026', 'SKLEP A TESTOWY', '-7,10', 1),
    ErsteStatements.tx(
      '09-03-2026',
      '09-03-2026',
      'Zakup BLIK SKLEP B TESTOWY ref:00000000001',
      'SKLEP B TESTOWY',
      '00 0000 0000 0000 0000 0000 0010',
      '-25,00',
      2,
    ),
    ErsteStatements.tx(
      '08-03-2026',
      '08-03-2026',
      'Przelew na rachunek własny',
      'FIRMA TESTOWA JAN TESTOWY UL. PRZYKŁADOWA 1/2 00-000 TESTOWO WOJ. TESTOWE',
      '00 0000 0000 0000 0000 0000 0002',
      '100,00',
      3,
    ),
    ErsteStatements.card('08-03-2026', '07-03-2026', 'SKLEP C TESTOWY', '-3,00', 4),
    ErsteStatements.card('06-03-2026', '06-03-2026', 'SKLEP D TESTOWY', '-1,00', 5),
  ];

  static Uint8List base() => ErsteStatements.bytes(baseRows());

  /// What the base statement adds to its account, in minor units.
  static const baseNet = -710 - 2500 + 10000 - 300 - 100;

  /// The base statement with field [field] of transaction row [row] (1-based) replaced.
  static Uint8List withField(int row, int field, String value) {
    final rows = baseRows();
    rows[row][field] = value;
    return ErsteStatements.bytes(rows);
  }

  /// The base statement with its transaction rows replaced by [rows].
  static Uint8List withRows(List<List<String>> rows) =>
      ErsteStatements.bytes([ErsteStatements.summary(), ...rows]);

  /// Every text value of [content]'s fields that could identify it, for the leak checks: each field
  /// of three characters or more, and every account number with its spaces removed.
  static Set<String> texts(Uint8List content) {
    final out = <String>{};
    for (final line in utf8.decode(content, allowMalformed: true).split('\n')) {
      for (final raw in line.split(',')) {
        final field = raw.replaceAll('"', '').replaceAll("'", '').trim();
        // A currency code is not statement text: every answer about a currency names one.
        if (field.length >= 3 &&
            !RegExp(r'^[0-9,\-.]+$').hasMatch(field) &&
            !RegExp(r'^[A-Z]{3}$').hasMatch(field)) {
          out.add(field);
        }
        // Each upper-case word of five letters or more alone: a merchant inside a card description.
        for (final word in field.split(RegExp(r'\s+'))) {
          if (word.length >= 5 && word == word.toUpperCase() && RegExp(r'[A-Z]').hasMatch(word)) {
            out.add(word);
          }
        }
        final digits = field.replaceAll(' ', '');
        if (RegExp(r'^[0-9]{26}$').hasMatch(digits)) out.add(digits);
      }
    }
    return out;
  }
}

/// One device with a real encrypted store — the ledger and its device-only import sessions — a clock the
/// test moves, and the ledger and workflow over them. Nothing is mocked.
final class ImportWorld {
  final Directory root;
  ZenStore zen;
  PrudentLocalStore store;
  Ledger ledger;
  late ImportWorkflow imports;
  int nowMs;

  ImportWorld._(this.root, this.zen, this.store, this.ledger, this.nowMs);

  /// 2026-11-16 at noon UTC: the golden file's "today".
  static const start = 1794830400000;

  static Future<ImportWorld> create({int maxOpenSessions = 10, int? maxRows}) async {
    final root = await Directory.systemTemp.createTemp('prudent_local_imports');
    final zen = ok(await _openLedger(root));
    final store = PrudentLocalStore(zen);
    final world = ImportWorld._(root, zen, store, Ledger(store), start);
    world.imports = world.workflow(maxOpenSessions: maxOpenSessions, maxRows: maxRows);
    return world;
  }

  ImportWorkflow workflow({int maxOpenSessions = 10, int? maxRows, ImportFaults? faults}) =>
      ImportWorkflow(
        ledger: store,
        nowMs: () => nowMs,
        maxOpenSessions: maxOpenSessions,
        maxRows: maxRows ?? 5000,
        faults: faults,
      );

  static final _ledgerKey = List.filled(32, 7);

  static Future<ZenResult<ZenStore>> _openLedger(
    Directory root, {
    Future<void> Function(int replaced, int total)? afterFileReplaced,
  }) => ZenStore.open(
    Directory('${root.path}/ledger'),
    deviceName: 'Phone',
    key: _ledgerKey,
    // ignore: invalid_use_of_visible_for_testing_member
    afterFileReplaced: afterFileReplaced,
  );

  /// Closes the store and opens it again from its directory, as a relaunch does — the way
  /// a crash is followed by the next start of the app. [afterFileReplaced] is jZen's test hook that
  /// stops a `writeAll` half way.
  Future<void> reopen({Future<void> Function(int replaced, int total)? afterFileReplaced}) async {
    await zen.close();
    zen = ok(await _openLedger(root, afterFileReplaced: afterFileReplaced));
    store = PrudentLocalStore(zen);
    ledger = Ledger(store);
    imports = workflow();
  }

  Future<void> dispose() async {
    await zen.close();
    await root.delete(recursive: true);
  }

  // ── The ledger a statement is imported into ────────────────────────────────────────────────

  /// An active account holding [currencies], numbered [number] when given.
  Future<String> account({
    String? number = Erste.account,
    List<String> currencies = const ['PLN'],
    bool active = true,
    String name = 'Erste',
  }) async {
    final request = wire.CreateAccountRequest(
      name: name,
      type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
      isActive: active,
      balances: [
        for (final c in currencies) wire.CurrencyBalance(currency: c, amountMinor: Int64.ZERO),
      ],
    );
    if (number != null) request.accountNumber = number;
    return ok(await ledger.createAccount(request)).value.id;
  }

  /// Gives account [id] the number [number] (none when null), keeping the rest as it is.
  Future<void> renumber(String id, String? number) async {
    final account = ok(await ledger.getAccount(id)).value;
    final request = wire.UpdateAccountRequest(
      name: account.name,
      type: account.type,
      isActive: account.isActive,
      includeInTotal: account.includeInTotal,
      includeInOverview: account.includeInOverview,
      balances: [
        for (final b in account.balances)
          wire.CurrencyBalance(currency: b.currency, amountMinor: Int64.ZERO),
      ],
    );
    if (number != null) request.accountNumber = number;
    ok(await ledger.updateAccount(id, request));
  }

  Future<String> category(String title, {wire.CategoryKind? kind}) async {
    final request = wire.CreateCategoryRequest(title: title, iconKey: 'food');
    if (kind != null) request.kind = kind;
    return ok(await ledger.createCategory(request)).id;
  }

  /// The ledger records, by id.
  Map<String, Record> records() => {for (final r in ok(store.records.list())) r.id: r};

  /// What [accountId] holds in PLN after its opening amount, from the ledger's own figure.
  Future<int> net(String accountId) async =>
      ok(await ledger.accountBalances(accountId)).minor['PLN']!;

  /// Every byte of the store's readable state: each collection's records and conflicts. Equal
  /// snapshots mean nothing was written.
  String snapshot() {
    final out = StringBuffer();
    void all<T extends GeneratedMessage>(String name, ZenCollection<T> c) {
      final values = ok(c.list()).map((v) => base64.encode(v.writeToBuffer())).toList()..sort();
      out.writeln('$name ${values.join(' ')} ${ok(c.conflicts()).length}');
    }

    all('accounts', store.accounts);
    all('account_currencies', store.accountCurrencies);
    all('categories', store.categories);
    all('records', store.records);
    all('transfers', store.transfers);
    all('settings', store.settings);
    all('import_sessions', store.importSessions);
    return out.toString();
  }

  // ── The workflow, as the screens call it ───────────────────────────────────────────────────

  Future<ZenResult<wire.ImportSession>> upload(Uint8List content, {String? account}) {
    final request = wire.CreateImportSessionRequest(formatId: 'erste-pl-csv', content: content);
    if (account != null) request.accountId = account;
    return imports.create(request);
  }

  Future<ZenResult<wire.ImportSession>> preview(String id, {String? account}) {
    final request = wire.PreviewImportSessionRequest();
    if (account != null) request.accountId = account;
    return imports.preview(id, request);
  }

  Future<ZenResult<wire.ImportSession>> defaults(String id, {String? expense, String? income}) {
    final request = wire.SetImportDefaultsRequest();
    if (expense != null) request.defaultExpenseCategoryId = expense;
    if (income != null) request.defaultIncomeCategoryId = income;
    return imports.setDefaults(id, request);
  }

  Future<ZenResult<wire.ImportSession>> commit(String id, int confirmed) =>
      imports.commit(id, wire.CommitImportSessionRequest(confirmedAcceptedRows: confirmed));

  Future<ZenResult<wire.UpdateImportRowResponse>> row(
    String id,
    int rowNumber, {
    String? category,
    String? note,
    bool? include,
  }) {
    final request = wire.UpdateImportRowRequest();
    if (category != null) request.categoryId = category;
    if (note != null) request.note = note;
    if (include != null) request.includeDuplicate = include;
    return imports.updateRow(id, rowNumber, request);
  }

  /// Uploads [content] into [account], previews it and sets both defaults: a session ready to
  /// commit, as the screens leave it.
  Future<wire.ImportSession> previewed(
    Uint8List content, {
    required String account,
    required String expense,
    required String income,
  }) async {
    final parsed = ok(await upload(content, account: account));
    final shown = ok(await preview(parsed.id));
    ok(await defaults(parsed.id, expense: expense, income: income));
    return shown;
  }
}
