// What a person can ask of the server about their own data (M0, jlogicsoftware/prudent#48): a
// readable copy of it, and its erasure. The two behaviours worth pinning are the ones a green
// screen would hide — that a REFUSED erasure leaves the person signed in with their data on the
// device, and that an ACCEPTED one leaves nothing of the account behind on it.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prudent/notification/local_notification_gateway.dart';
import 'package:prudent/notification/notification_providers.dart';
import 'package:prudent/notification/reminder_notification.dart';
import 'package:prudent/privacy/privacy_actions.dart';
import 'package:prudent/providers.dart';
import 'package:prudent/prudent_repository.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_identity/zen_identity.dart';
import 'package:zen_transport/zen_transport.dart' hide ZenError;
import 'package:zen_ui_identity/zen_ui_identity.dart';

/// An identity repository that is signed out of nothing and counts how often it is asked to sign
/// the user out.
class _CountingIdentityRepository implements IdentityRepository {
  int logouts = 0;

  @override
  Future<ZenResult<IdentityContract?>> getCurrentIdentity() async => const ZenResult.ok(null);

  @override
  Future<ZenResult<void>> logout() async {
    logouts++;
    return const ZenResult.ok(null);
  }

  @override
  Future<ZenResult<IdentityContract>> loginWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> registerWithEmail({
    required String email,
    required String password,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<void>> restorePassword({required String email}) async =>
      const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> confirmEmailLink({
    required String tokenHash,
    required String type,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> exchangeLinkSession({
    required String accessToken,
    String? refreshToken,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<void>> setPassword({
    required String password,
    String? currentPassword,
  }) async => const ZenResult.err(ZenUnknownError('not used'));

  @override
  Future<ZenResult<IdentityContract>> refreshSession() async =>
      const ZenResult.err(ZenUnknownError('not used'));
}

/// A device that has two reminder notifications pending, and remembers which were cancelled.
class _Device implements LocalNotificationGateway {
  final Set<int> pending = {1, 2};
  final List<int> cancelled = [];

  @override
  bool get isSupported => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ReminderNotification notification) async =>
      pending.add(notification.id);

  @override
  Future<Set<int>> pendingIds() async => {...pending};

  @override
  Future<void> cancel(int id) async {
    pending.remove(id);
    cancelled.add(id);
  }
}

void main() {
  late List<String> calls;
  late Map<String, Object?> erasureBody;
  late _CountingIdentityRepository identity;
  late _Device device;
  late ProviderContainer container;

  /// [eraseStatus] is what the server answers the erase call with.
  void build({required int eraseStatus}) {
    calls = [];
    erasureBody = {};
    identity = _CountingIdentityRepository();
    device = _Device();
    const headers = {'X-Zen-Transport': 'json'};
    final client = ZenClient(
      baseUrl: 'https://example.test',
      format: ZenTransportFormat.json,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');
        if (path == '/api/v1/privacy/export') {
          return http.Response(
            jsonEncode({
              'formatVersion': 1,
              'exportedAtMs': '1760000000000',
              'profile': {'email': 'alice@example.com'},
              'records': [
                {'id': 'r1', 'title': 'Coffee', 'amountMinor': '-450', 'currency': 'PLN'},
              ],
            }),
            200,
            headers: headers,
          );
        }
        if (path == '/api/v1/privacy/erase') {
          erasureBody = jsonDecode(request.body) as Map<String, Object?>;
          if (eraseStatus == 204) return http.Response('', 204, headers: headers);
          return http.Response(
            jsonEncode({
              'code': 'invalid',
              'message': 'Enter the email address of this account to confirm. Nothing was deleted.',
            }),
            eraseStatus,
            headers: headers,
          );
        }
        return http.Response(jsonEncode({'accounts': []}), 200, headers: headers);
      }),
    );
    container = ProviderContainer(
      overrides: [
        prudentRepositoryProvider.overrideWithValue(PrudentRepository(client: client)),
        identityRepositoryProvider.overrideWithValue(identity),
        localNotificationGatewayProvider.overrideWithValue(device),
      ],
    );
    addTearDown(container.dispose);
  }

  test('the export is indented JSON in the API\'s own field names', () async {
    build(eraseStatus: 204);

    final text = await container.read(privacyActionsProvider).exportJson();

    // Readable: more than one line, so a person can open it rather than squint at a single run.
    expect(text.split('\n').length, greaterThan(5));
    final document = jsonDecode(text) as Map<String, dynamic>;
    expect((document['profile'] as Map)['email'], 'alice@example.com');
    final record = (document['records'] as List).single as Map;
    expect(record['title'], 'Coffee');
    // Money is minor units and travels as the API spells it, never a float.
    expect(record['amountMinor'], '-450');
  });

  test('a failed export is the server\'s error, not an empty document', () async {
    build(eraseStatus: 204);
    final failing = ProviderContainer(
      overrides: [
        prudentRepositoryProvider.overrideWithValue(
          PrudentRepository(
            client: ZenClient(
              baseUrl: 'https://example.test',
              format: ZenTransportFormat.json,
              httpClient: MockClient(
                (_) async => http.Response(
                  jsonEncode({'code': 'unauthorized', 'message': 'Sign in again.'}),
                  401,
                  headers: const {'X-Zen-Transport': 'json'},
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(failing.dispose);

    expect(failing.read(privacyActionsProvider).exportJson(), throwsA(isA<ZenError>()));
  });

  test('an accepted erasure sends the address, drops the caches, cancels reminders, signs out', () async {
    build(eraseStatus: 204);
    await container.read(accountsProvider.future);
    expect(calls.where((c) => c == 'GET /api/v1/accounts').length, 1);

    await container.read(privacyActionsProvider).erase('alice@example.com');

    expect(erasureBody['confirmEmail'], 'alice@example.com');
    // Nothing the erased account scheduled may still fire on this device.
    expect(device.pending, isEmpty);
    expect(device.cancelled.toSet(), {1, 2});
    expect(identity.logouts, 1);
    // The cache was dropped: the next reader asks the server again instead of showing erased data.
    await container.read(accountsProvider.future);
    expect(calls.where((c) => c == 'GET /api/v1/accounts').length, 2);
  });

  test('a refused erasure changes nothing on the device and does not sign out', () async {
    build(eraseStatus: 400);
    await container.read(accountsProvider.future);

    await expectLater(
      container.read(privacyActionsProvider).erase('someone@else.example'),
      throwsA(
        isA<ZenError>().having((e) => e.message, 'message', contains('Nothing was deleted')),
      ),
    );

    expect(device.pending, {1, 2}, reason: 'a refused erasure cancelled reminders');
    expect(identity.logouts, 0, reason: 'a refused erasure signed the person out');
    await container.read(accountsProvider.future);
    expect(
      calls.where((c) => c == 'GET /api/v1/accounts').length,
      1,
      reason: 'a refused erasure dropped the cache',
    );
  });
}
