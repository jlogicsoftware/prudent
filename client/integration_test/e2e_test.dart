@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

// The living end-to-end test stand (docs/prudent-migration-prompt.md phase 5 §3). A pure-Dart VM
// suite (package:test, no flutter) so it runs headless and cheap under `dart test` in CI (task
// test:e2e), yet exercises the same zen_transport / SupabaseIdentityRepository /
// PrudentRepository code the app uses — including the native cookie jar, because the VM is a
// dart:io platform. No mocks: every call hits the live Quarkus + Supabase stack.
//
// NOTHING IN THIS FILE'S IMPORT GRAPH MAY REACH dart:ui — this runs on the plain Dart VM via
// `dart test`, not `flutter test`. A Flutter plugin anywhere in that graph does not degrade the
// gate, it ends it (it will not even compile under `dart test`).
//
// What it asserts end to end: register (which seeds the default categories and settings row via
// zen-identity's UserRegistered event, ADR-010), the session cookie surviving across requests,
// an account created, a record created against it and read back with the derived balance moved,
// and a typed round trip in BOTH transport modes on the records endpoint.
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart' show ZenResult;
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart';

import 'package:prudent/generated/prudent/v1/accounts.pb.dart';
import 'package:prudent/generated/prudent/v1/categories.pb.dart';
import 'package:prudent/generated/prudent/v1/records.pb.dart';
import 'package:prudent/prudent_repository.dart';

void main() {
  // ZEN_API_URL is read at RUNTIME here (Platform.environment), not via --dart-define: this is a
  // VM test harness rather than the shipped client bundle, so the compile-time-config rule (which
  // exists for the app bundle's tree-shaking) does not apply, and `dart test` does not forward
  // --define to the compiled test anyway. Falls back to zenApiUrl (:8085, ADR-010) for a local run
  // outside the Taskfile.
  final baseUrl = Platform.environment['ZEN_API_URL'] ?? zenApiUrl;
  final email = 'prudent-e2e-${DateTime.now().microsecondsSinceEpoch}@example.com';
  const password = 'secret123';

  late ZenSessionClient session;
  late SupabaseIdentityRepository identity;
  late PrudentRepository prudent;
  late String categoryId;
  late String accountId;

  T unwrap<T>(ZenResult<T> result, String what) {
    expect(result.isSuccess, isTrue, reason: '$what should succeed: ${result.errorOrNull?.message}');
    return result.dataOrNull as T;
  }

  setUpAll(() async {
    session = createSessionClient();
    // Wired exactly as main.dart wires it, including the 401 -> renew -> replay loop: a gate
    // that exercised a differently assembled client would prove less than it appears to.
    Future<bool> recoverSession() async => (await identity.refreshSession()).isSuccess;
    identity = SupabaseIdentityRepository(
      client: ZenClient(baseUrl: baseUrl, httpClient: session, recoverSession: recoverSession),
    );
    prudent = PrudentRepository(
      client: ZenClient(baseUrl: baseUrl, httpClient: session, recoverSession: recoverSession),
    );

    // Register a fresh user; with local Supabase auto-confirm this logs in and sets the cookies.
    // Registration is also what fires zen-identity's UserRegistered event, which seeds Prudent's
    // five default categories and Settings row (docs/DECISIONS.md ADR-010) — nothing else creates
    // them, so a category must be listed back before it can be used below.
    final registered = await identity.registerWithEmail(email: email, password: password);
    expect(
      registered.isSuccess,
      isTrue,
      reason: 'register should succeed against the live stack: ${registered.errorOrNull?.message}',
    );

    // NewUserSetup is a jZen @ObservesAsync observer (ADR-010 "the framework's event"), so the
    // seeding genuinely races the registration response — measured here, not assumed: the first
    // run of this suite caught the response returning zero categories. Polling is the correct
    // fix, not a longer fixed sleep: the wait time depends on machine load, not on a constant.
    List<Category> categories = const [];
    for (var attempt = 0; attempt < 20 && categories.isEmpty; attempt++) {
      categories = unwrap(await prudent.listCategories(), 'listing seeded categories').categories;
      if (categories.isEmpty) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(categories, isNotEmpty, reason: 'registration must (eventually) seed default categories');
    categoryId = categories.first.id;
  });

  tearDownAll(() {
    session.close();
  });

  test('the session cookie survives across requests (getCurrentIdentity)', () async {
    final current = await identity.getCurrentIdentity();
    expect(current.isSuccess, isTrue);
    final model = current.dataOrNull;
    expect(model, isNotNull, reason: 'the registration cookie must be resent on native');
    expect(model!.id, isNotEmpty);
  });

  test('an account can be created with an opening PLN balance', () async {
    final account = unwrap(
      await prudent.createAccount(
        CreateAccountRequest(
          name: 'E2E checking',
          type: AccountType.ACCOUNT_TYPE_CHECKING,
          isActive: true,
          includeInTotal: true,
          includeInOverview: true,
          balances: [CurrencyBalance(currency: 'PLN', amountMinor: Int64(10000))],
        ),
      ),
      'creating an account',
    );
    expect(account.id, isNotEmpty);
    expect(account.balances.single.amountMinor.toInt(), 10000);
    accountId = account.id;
  });

  test('a record is created, moves the account balance, and reads back', () async {
    final created = unwrap(
      await prudent.createRecord(
        CreateRecordRequest(
          title: 'E2E grocery run',
          amountMinor: Int64(-2500),
          date: '2026-08-18',
          categoryId: categoryId,
          accountId: accountId,
          currency: 'PLN',
        ),
      ),
      'creating a record',
    );
    expect(created.id, isNotEmpty);
    expect(created.amountMinor.toInt(), -2500);

    final listed = unwrap(await prudent.listRecords(), 'reading records back');
    expect(listed.records.map((r) => r.id), contains(created.id));

    // The derived-balance formula (ADR-014): opening 10000 - 2500 = 7500, computed server-side on
    // every read, never written back to a column.
    final account = unwrap(await prudent.listAccounts(), 'reading accounts back');
    final updated = account.accounts.singleWhere((a) => a.id == accountId);
    expect(updated.balances.single.amountMinor.toInt(), 7500);
  });

  test('the records endpoint round-trips in both transport modes', () async {
    Future<bool> recoverSession() async => (await identity.refreshSession()).isSuccess;

    final jsonRepo = PrudentRepository(
      client: ZenClient(
        baseUrl: baseUrl,
        httpClient: session,
        format: ZenTransportFormat.json,
        recoverSession: recoverSession,
      ),
    );
    final protobufRepo = PrudentRepository(
      client: ZenClient(
        baseUrl: baseUrl,
        httpClient: session,
        format: ZenTransportFormat.protobuf,
        recoverSession: recoverSession,
      ),
    );

    final jsonResult = unwrap(await jsonRepo.listRecords(), 'listing records in JSON mode');
    final protobufResult = unwrap(
      await protobufRepo.listRecords(),
      'listing records in Protobuf mode',
    );

    expect(jsonResult.records, isNotEmpty);
    expect(
      jsonResult.records.map((r) => r.id).toSet(),
      protobufResult.records.map((r) => r.id).toSet(),
      reason: 'both transport modes must decode to the same records',
    );
  });

  test('an anonymous request is refused', () async {
    final anonSession = createSessionClient();
    addTearDown(anonSession.close);
    final anon = PrudentRepository(client: ZenClient(baseUrl: baseUrl, httpClient: anonSession));

    final result = await anon.listRecords();
    expect(result.isFailure, isTrue);
    expect(result.errorOrNull!.message, isNotEmpty);
  });

  test('logout clears the session', () async {
    final loggedOut = await identity.logout();
    expect(loggedOut.isSuccess, isTrue);

    final current = await identity.getCurrentIdentity();
    expect(current.isSuccess, isTrue);
    expect(current.dataOrNull, isNull, reason: 'logout must clear the session cookie');
  });
}
